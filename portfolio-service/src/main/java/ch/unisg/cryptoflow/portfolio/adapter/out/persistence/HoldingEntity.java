package ch.unisg.cryptoflow.portfolio.adapter.out.persistence;

import jakarta.persistence.*;
import lombok.Getter;

import java.math.BigDecimal;
import java.time.Instant;

@Getter
@Entity
@Table(name = "holding")
public class HoldingEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String symbol;

    @Column(nullable = false, precision = 30, scale = 18)
    private BigDecimal quantity;

    @Column(nullable = false, precision = 30, scale = 8)
    private BigDecimal averagePurchasePrice;

    @Column(name = "added_at", nullable = false, updatable = false)
    private Instant addedAt;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "portfolio_id", nullable = false)
    private PortfolioEntity portfolio;

    protected HoldingEntity() {}

    public HoldingEntity(String symbol, BigDecimal quantity,
                         BigDecimal averagePurchasePrice, PortfolioEntity portfolio) {
        this.symbol = symbol;
        this.quantity = quantity;
        this.averagePurchasePrice = averagePurchasePrice;
        this.portfolio = portfolio;
        this.addedAt = Instant.now();
    }

    /** Called on subsequent purchases: updates quantity and recalculates the weighted average price. */
    public void updateQuantityAndPrice(BigDecimal newQuantity, BigDecimal newAveragePrice) {
        this.quantity = newQuantity;
        this.averagePurchasePrice = newAveragePrice;
    }
}
