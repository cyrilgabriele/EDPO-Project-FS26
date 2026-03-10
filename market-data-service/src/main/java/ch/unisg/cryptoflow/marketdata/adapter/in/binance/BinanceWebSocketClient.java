package ch.unisg.cryptoflow.marketdata.adapter.in.binance;

import ch.unisg.cryptoflow.marketdata.adapter.out.kafka.CryptoPriceKafkaProducer;
import ch.unisg.cryptoflow.marketdata.application.PriceEventMapper;
import ch.unisg.cryptoflow.marketdata.domain.PriceTick;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketHttpHeaders;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.math.BigDecimal;
import java.net.URI;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

/**
 * Inbound adapter – subscribes to Binance WebSocket ticker streams and forwards
 * each price update to Kafka via {@link CryptoPriceKafkaProducer}.
 *
 * <p>Binance pushes real-time ticker updates over a persistent WebSocket
 * connection. This makes the market-data-service event-driven end-to-end:
 * Binance pushes → we map → we publish to Kafka.
 *
 * <p>The connection is opened on startup. If it drops, the client reconnects
 * automatically with exponential backoff (1 s, 2 s, 4 s, … up to 60 s).
 *
 * <p>This demonstrates the <strong>Event Notification</strong> pattern:
 * the producer emits events with no knowledge of who consumes them.
 */
@Component
public class BinanceWebSocketClient extends TextWebSocketHandler {

    private static final Logger log = LoggerFactory.getLogger(BinanceWebSocketClient.class);
    private static final long INITIAL_BACKOFF_MS = 1_000;
    private static final long MAX_BACKOFF_MS = 60_000;

    private final PriceEventMapper priceEventMapper;
    private final CryptoPriceKafkaProducer kafkaProducer;
    private final ObjectMapper objectMapper;
    private final String streamUrl;
    private final List<String> symbols;

    private final ScheduledExecutorService reconnectExecutor = Executors.newSingleThreadScheduledExecutor();
    private volatile WebSocketSession session;
    private volatile long currentBackoffMs = INITIAL_BACKOFF_MS;
    private volatile boolean shuttingDown = false;

    public BinanceWebSocketClient(
            PriceEventMapper priceEventMapper,
            CryptoPriceKafkaProducer kafkaProducer,
            ObjectMapper objectMapper,
            @Value("${binance.stream-url}") String streamUrl,
            @Value("${binance.symbols}") List<String> symbols) {
        this.priceEventMapper = priceEventMapper;
        this.kafkaProducer = kafkaProducer;
        this.objectMapper = objectMapper;
        this.streamUrl = streamUrl;
        this.symbols = symbols;
    }

    @PostConstruct
    public void connect() {
        if (symbols.isEmpty()) {
            log.warn("No symbols configured – WebSocket connection will not be opened");
            return;
        }
        doConnect();
    }

    @PreDestroy
    public void shutdown() {
        shuttingDown = true;
        reconnectExecutor.shutdownNow();
        closeSession();
    }

    private void doConnect() {
        String streams = symbols.stream()
                .map(s -> s.toLowerCase() + "@ticker")
                .collect(Collectors.joining("/"));
        String uri = streamUrl + "/" + streams;

        log.info("Connecting to Binance WebSocket: {}", uri);

        try {
            var client = new StandardWebSocketClient();
            client.execute(this, new WebSocketHttpHeaders(), URI.create(uri));
        } catch (Exception e) {
            log.error("Failed to initiate WebSocket connection: {}", e.getMessage());
            scheduleReconnect();
        }
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) {
        this.session = session;
        this.currentBackoffMs = INITIAL_BACKOFF_MS;
        log.info("Binance WebSocket connected (session: {}, symbols: {})", session.getId(), symbols);
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) {
        try {
            JsonNode node = objectMapper.readTree(message.getPayload());

            String symbol = node.path("s").asText(null);
            String priceStr = node.path("c").asText(null);

            if (symbol == null || priceStr == null) {
                log.debug("Ignoring message without symbol/price fields: {}", message.getPayload());
                return;
            }

            var tick = new PriceTick(symbol, new BigDecimal(priceStr));
            var event = priceEventMapper.toEvent(tick);
            kafkaProducer.publish(event);

        } catch (Exception e) {
            log.warn("Failed to process Binance WebSocket message: {}", e.getMessage());
        }
    }

    @Override
    public void handleTransportError(WebSocketSession session, Throwable exception) {
        log.warn("Binance WebSocket transport error: {}", exception.getMessage());
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        this.session = null;
        if (!shuttingDown) {
            log.warn("Binance WebSocket disconnected (status: {}). Scheduling reconnect.", status);
            scheduleReconnect();
        }
    }

    private void scheduleReconnect() {
        if (shuttingDown) return;

        log.info("Reconnecting in {} ms", currentBackoffMs);
        reconnectExecutor.schedule(this::doConnect, currentBackoffMs, TimeUnit.MILLISECONDS);
        currentBackoffMs = Math.min(currentBackoffMs * 2, MAX_BACKOFF_MS);
    }

    private void closeSession() {
        var s = this.session;
        if (s != null && s.isOpen()) {
            try {
                s.close();
            } catch (Exception e) {
                log.debug("Error closing WebSocket session: {}", e.getMessage());
            }
        }
    }
}
