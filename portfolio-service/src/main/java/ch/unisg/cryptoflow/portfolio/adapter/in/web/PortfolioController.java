package ch.unisg.cryptoflow.portfolio.adapter.in.web;

import ch.unisg.cryptoflow.portfolio.adapter.out.persistence.HoldingEntity;
import ch.unisg.cryptoflow.portfolio.adapter.out.persistence.PortfolioEntity;
import ch.unisg.cryptoflow.portfolio.application.PortfolioService;
import ch.unisg.cryptoflow.portfolio.domain.LocalPriceCache;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * CQRS read-side REST controller for portfolio queries.
 *
 * <p>All valuations are computed using the {@link LocalPriceCache} (ECST) –
 * no synchronous call is made to {@code market-data-service}.
 */
@RestController
@RequestMapping("/portfolios")
public class PortfolioController {

    private final PortfolioService portfolioService;
    private final LocalPriceCache localPriceCache;

    public PortfolioController(PortfolioService portfolioService,
                               LocalPriceCache localPriceCache) {
        this.portfolioService = portfolioService;
        this.localPriceCache = localPriceCache;
    }

    /** Returns the portfolio with current valuation per holding. */
    @GetMapping("/{userId}")
    public ResponseEntity<Object> getPortfolio(@PathVariable String userId) {
        return portfolioService.getPortfolio(userId)
                .<ResponseEntity<Object>>map(p -> ResponseEntity.ok(toResponse(p)))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /** Returns the total portfolio value in USDT, calculated from the local price cache. */
    @GetMapping("/{userId}/value")
    public ResponseEntity<Object> getPortfolioValue(@PathVariable String userId) {
        if (portfolioService.getPortfolio(userId).isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        Optional<BigDecimal> value = portfolioService.calculateTotalValue(userId);
        if (value.isEmpty()) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(Map.of("error",
                            "One or more symbol prices are not yet cached. " +
                            "The market-data-service may still be warming up."));
        }
        return ResponseEntity.ok(Map.of(
                "userId", userId,
                "totalValueUsdt", value.get()
        ));
    }

    private Map<String, Object> toResponse(PortfolioEntity portfolio) {
        List<Map<String, Object>> holdings = portfolio.getHoldings().stream()
                .map(this::holdingToMap)
                .toList();
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("userId", portfolio.getUserId());
        response.put("userName", portfolio.getUserName());
        response.put("holdings", holdings);
        return response;
    }

    private Map<String, Object> holdingToMap(HoldingEntity holding) {
        Optional<BigDecimal> price = localPriceCache.getPrice(holding.getSymbol());
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("symbol", holding.getSymbol());
        map.put("quantity", holding.getQuantity());
        map.put("averagePurchasePrice", holding.getAveragePurchasePrice());
        price.ifPresent(p -> {
            map.put("currentPrice", p);
            map.put("currentValue", holding.getQuantity().multiply(p));
        });
        return map;
    }
}
