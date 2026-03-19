package ch.unisg.cryptoflow.transaction.adapter.in.camunda.job;

import java.util.Map;

public record OrderProcessingVariables(String symbol, String amount, String price) {

    public static OrderProcessingVariables fromMap(Map<String, Object> map) {
        return new OrderProcessingVariables(
                (String) map.get("symbol"),
                (String) map.get("amount"),
                (String) map.get("price")
        );
    }

    public Map<String, Object> toMap() {
        return Map.of(
                "symbol", symbol,
                "amount", amount,
                "price", price
        );
    }
}
