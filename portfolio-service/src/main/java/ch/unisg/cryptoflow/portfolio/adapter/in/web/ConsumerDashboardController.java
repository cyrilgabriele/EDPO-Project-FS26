package ch.unisg.cryptoflow.portfolio.adapter.in.web;

import ch.unisg.cryptoflow.portfolio.adapter.out.persistence.PortfolioRepository;
import ch.unisg.cryptoflow.portfolio.domain.LocalPriceCache;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Exposes dashboard data for the static demo page at {@code /}.
 * Returns metadata about the ECST pattern, the current local price cache snapshot,
 * and all portfolios with their current holdings and valuations.
 */
@RestController
@RequestMapping("/api/dashboard")
public class ConsumerDashboardController {

    private final LocalPriceCache localPriceCache;
    private final PortfolioRepository portfolioRepository;
    private final String topic;
    private final String groupId;

    public ConsumerDashboardController(
            LocalPriceCache localPriceCache,
            PortfolioRepository portfolioRepository,
            @Value("${crypto.kafka.topic.price-raw}") String topic,
            @Value("${spring.kafka.consumer.group-id}") String groupId) {
        this.localPriceCache = localPriceCache;
        this.portfolioRepository = portfolioRepository;
        this.topic = topic;
        this.groupId = groupId;
    }

    @GetMapping
    public Map<String, Object> dashboard() {
        List<Map<String, Object>> portfolios = portfolioRepository.findAll().stream()
                .map(portfolio -> {
                    List<Map<String, Object>> holdings = portfolio.getHoldings().stream()
                            .map(h -> {
                                Optional<BigDecimal> price = localPriceCache.getPrice(h.getSymbol());
                                Map<String, Object> holding = new LinkedHashMap<>();
                                holding.put("symbol", h.getSymbol());
                                holding.put("quantity", h.getQuantity().stripTrailingZeros().toPlainString());
                                holding.put("avgPrice", h.getAveragePurchasePrice().toPlainString());
                                price.ifPresentOrElse(
                                        p -> {
                                            holding.put("currentPrice", p.toPlainString());
                                            holding.put("currentValue",
                                                    h.getQuantity().multiply(p)
                                                            .setScale(2, RoundingMode.HALF_UP).toPlainString());
                                        },
                                        () -> {
                                            holding.put("currentPrice", "");
                                            holding.put("currentValue", "");
                                        }
                                );
                                holding.put("addedAt", h.getAddedAt() != null ? h.getAddedAt().toString() : "");
                                return holding;
                            })
                            .toList();

                    BigDecimal total = holdings.stream()
                            .map(h -> (String) h.get("currentValue"))
                            .filter(v -> v != null && !v.isEmpty())
                            .map(BigDecimal::new)
                            .reduce(BigDecimal.ZERO, BigDecimal::add);

                    Map<String, Object> p = new LinkedHashMap<>();
                    p.put("userId",     portfolio.getUserId());
                    p.put("userName",   portfolio.getUserName() != null ? portfolio.getUserName() : "");
                    p.put("holdings",   holdings);
                    p.put("totalValue", total.compareTo(BigDecimal.ZERO) > 0
                            ? total.setScale(2, RoundingMode.HALF_UP).toPlainString() : "");
                    return p;
                })
                .toList();

        return Map.of(
                "service",    "portfolio-service",
                "pattern",    "Event-Carried State Transfer (ECST)",
                "topic",      topic,
                "groupId",    groupId,
                "cacheSize",  localPriceCache.getAllPrices().size(),
                "prices",     localPriceCache.getAllPrices(),
                "portfolios", portfolios
        );
    }
}
