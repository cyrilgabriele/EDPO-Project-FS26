package com.examples;



import com.google.common.io.Resources;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;

import java.io.IOException;
import java.io.InputStream;
import java.time.Duration;
import java.util.Arrays;
import java.util.Map;
import java.util.Properties;

public class ClicksConsumer {
    public static void main(String[] args) throws IOException {

        // Read Kafka properties file and create Kafka consumer with the given properties
        KafkaConsumer<String, Object> consumer;
        try (InputStream props = Resources.getResource("consumer.properties").openStream()) {
            Properties properties = new Properties();
            properties.load(props);
            consumer = new KafkaConsumer<>(properties);
        }

        // subscribe to relevant topics
        consumer.subscribe(Arrays.asList("click-events"));

        Integer previousEventId = null;

        while (true) {

            // pool new data
            ConsumerRecords<String, Object> records = consumer.poll(Duration.ofMillis(8));

            // process consumer records depending on record.topic() and record.value()
            for (ConsumerRecord<String, Object> record : records) {
                if ("click-events".equals(record.topic())) {
                    Integer currentEventId = extractEventId(record.value());
                    if (currentEventId != null && previousEventId != null && currentEventId > previousEventId + 1) {
                        System.out.println("GAP DETECTED from=" + (previousEventId + 1) + " to="
                                + (currentEventId - 1) + " previous=" + previousEventId
                                + " current=" + currentEventId);
                    }
                    if (currentEventId != null) {
                        previousEventId = currentEventId;
                    }
                    System.out.println("RECEIVED eventID=" + currentEventId
                            + " partition=" + record.partition()
                            + " offset=" + record.offset()
                            + " value=" + record.value());
                } else {
                    throw new IllegalStateException("Shouldn't be possible to get message on topic " + record.topic());
                }
            }

            if (!records.isEmpty()) {
                consumer.commitSync();
            }

        }
    }

    private static Integer extractEventId(Object value) {
        if (value instanceof Map<?, ?> valueMap) {
            Object eventId = valueMap.get("eventID");
            if (eventId instanceof Number numberValue) {
                return numberValue.intValue();
            }
        }
        return null;
    }

}

