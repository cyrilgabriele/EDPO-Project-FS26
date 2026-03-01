package ch.unisg.kafka.spring.service;

import ch.unisg.kafka.spring.model.BinanceRollingWindowTicker;
import ch.unisg.kafka.spring.model.MarketRollingWindowEvent;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;

import jakarta.annotation.PreDestroy;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.WebSocket;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

@Service
public class MarketRollingWindowIngestService {

    private static final Logger log = LoggerFactory.getLogger(MarketRollingWindowIngestService.class);
    private static final TypeReference<List<BinanceRollingWindowTicker>> TICKER_LIST_TYPE = new TypeReference<>() {};
    private static final String SOURCE = "binance";

    private final KafkaTemplate<String, MarketRollingWindowEvent> kafkaTemplate;
    private final ObjectMapper objectMapper;
    private final HttpClient httpClient;
    private final URI streamUri;
    private final String windowLabel;
    private final String topic;
    private final Duration reconnectDelay;

    private final ScheduledExecutorService reconnectExecutor = Executors.newSingleThreadScheduledExecutor(r -> {
        Thread thread = new Thread(r, "binance-ws-reconnect");
        thread.setDaemon(true);
        return thread;
    });

    private final AtomicBoolean running = new AtomicBoolean(false);
    private final AtomicBoolean connecting = new AtomicBoolean(false);
    private volatile WebSocket currentSession;

    public MarketRollingWindowIngestService(
            @Qualifier("marketRollingKafkaTemplate") KafkaTemplate<String, MarketRollingWindowEvent> kafkaTemplate,
            ObjectMapper objectMapper,
            @Value("${app.kafka.market-rolling-topic}") String topic,
            @Value("${app.binance.ws-base-url}") String wsBaseUrl,
            @Value("${app.binance.stream-name}") String streamName,
            @Value("${app.binance.reconnect-delay:5s}") Duration reconnectDelay
    ) {
        this.kafkaTemplate = kafkaTemplate;
        this.objectMapper = objectMapper;
        this.topic = topic;
        this.reconnectDelay = reconnectDelay;
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(15))
                .build();
        this.streamUri = buildStreamUri(wsBaseUrl, streamName);
        this.windowLabel = deriveWindowLabel(streamName);
    }

    @EventListener(ApplicationReadyEvent.class)
    public void start() {
        if (running.compareAndSet(false, true)) {
            log.info("Starting Binance market ingest for stream {}", streamUri);
            connect();
        }
    }

    private void connect() {
        if (!running.get()) {
            return;
        }
        if (!connecting.compareAndSet(false, true)) {
            return;
        }

        httpClient.newWebSocketBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .buildAsync(streamUri, new BinanceStreamListener())
                .whenComplete((session, error) -> {
                    connecting.set(false);
                    if (error != null) {
                        log.warn("Unable to establish Binance stream connection", error);
                        scheduleReconnect();
                    } else {
                        log.info("Binance stream connection open");
                        this.currentSession = session;
                    }
                });
    }

    private void scheduleReconnect() {
        if (!running.get()) {
            return;
        }
        reconnectExecutor.schedule(() -> {
            log.info("Reconnecting to Binance stream {}", streamUri);
            connect();
        }, reconnectDelay.toMillis(), TimeUnit.MILLISECONDS);
    }

    private void handlePayload(String payload) {
        if (!running.get() || payload == null || payload.isBlank()) {
            return;
        }
        try {
            List<BinanceRollingWindowTicker> deltas = objectMapper.readValue(payload, TICKER_LIST_TYPE);
            if (deltas == null || deltas.isEmpty()) {
                return;
            }
            deltas.stream()
                    .filter(Objects::nonNull)
                    .forEach(this::publishDelta);
        } catch (Exception e) {
            log.error("Failed to parse Binance payload", e);
        }
    }

    private void publishDelta(BinanceRollingWindowTicker delta) {
        if (delta.symbol() == null || delta.symbol().isBlank()) {
            log.debug("Skipping Binance delta without symbol: {}", delta);
            return;
        }
        MarketRollingWindowEvent event = new MarketRollingWindowEvent(
                SOURCE,
                windowLabel,
                Instant.ofEpochMilli(delta.eventTime()),
                delta
        );

        log.info("Publishing Binance delta for {} at close price {}", delta.symbol(), delta.closePrice());

        kafkaTemplate.send(topic, delta.symbol(), event)
                .whenComplete((result, throwable) -> {
                    if (throwable != null) {
                        log.error("Failed to publish delta for symbol {}", delta.symbol(), throwable);
                    }
                });
    }

    private URI buildStreamUri(String baseUrl, String streamName) {
        String sanitizedBase = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
        return URI.create(String.format("%s/%s", sanitizedBase, streamName));
    }

    private String deriveWindowLabel(String streamName) {
        int start = streamName.indexOf('_');
        int end = streamName.indexOf('@', start + 1);
        if (start >= 0 && end > start) {
            return streamName.substring(start + 1, end);
        }
        return streamName;
    }

    @PreDestroy
    public void shutdown() {
        running.set(false);
        if (currentSession != null) {
            try {
                currentSession.sendClose(WebSocket.NORMAL_CLOSURE, "Application shutdown").get(5, TimeUnit.SECONDS);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                log.debug("Interrupted while closing Binance WebSocket", ie);
            } catch (Exception e) {
                log.debug("Error closing Binance WebSocket", e);
                currentSession.abort();
            }
        }
        reconnectExecutor.shutdownNow();
    }

    private final class BinanceStreamListener implements WebSocket.Listener {
        private final StringBuilder buffer = new StringBuilder();

        @Override
        public void onOpen(WebSocket webSocket) {
            webSocket.request(1);
        }

        @Override
        public CompletionStage<?> onText(WebSocket webSocket, CharSequence data, boolean last) {
            buffer.append(data);
            if (last) {
                String message = buffer.toString();
                buffer.setLength(0);
                handlePayload(message);
            }
            webSocket.request(1);
            return CompletableFuture.completedFuture(null);
        }

        @Override
        public CompletionStage<?> onClose(WebSocket webSocket, int statusCode, String reason) {
            log.info("Binance WebSocket closed: {} - {}", statusCode, reason);
            MarketRollingWindowIngestService.this.currentSession = null;
            scheduleReconnect();
            return CompletableFuture.completedFuture(null);
        }

        @Override
        public void onError(WebSocket webSocket, Throwable error) {
            log.error("Binance WebSocket error", error);
            MarketRollingWindowIngestService.this.currentSession = null;
            scheduleReconnect();
        }
    }
}
