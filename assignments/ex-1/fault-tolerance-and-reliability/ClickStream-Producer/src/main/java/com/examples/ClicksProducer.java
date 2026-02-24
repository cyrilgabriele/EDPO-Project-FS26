package com.examples;


import com.data.Clicks;
import com.google.common.io.Resources;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.DeleteTopicsResult;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.Node;

import java.io.InputStream;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;


public class ClicksProducer {
    private static final DateTimeFormatter TS_FORMATTER =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS");

    public static void main(String[] args) throws Exception {

        // Specify Topic
        String topic = "click-events";

        // Read Kafka properties file
        Properties properties;
        try (InputStream props = Resources.getResource("producer.properties").openStream()) {
            properties = new Properties();
            properties.load(props);
        }

        // Create Kafka producer
        KafkaProducer<String, Clicks> producer = new KafkaProducer<>(properties);

        /// delete existing topic with the same name
        deleteTopic(topic, properties);

        // create new topic with 1 partition and replication factor of 3
        createTopic(topic, 1, 3, properties);

        int previousLeaderId = -1;

        try {

            // Define a counter which will be used as an eventID
            int counter = 0;

            // Create AdminClient once outside the loop for monitoring
            AdminClient adminClient = AdminClient.create(properties);


            // Variable to track changes in ISR (so we don't print on every loop if nothing changed)
            String previousIsrString = "";
            String previousClusterNodes = "";
            AtomicLong failoverStartMs = new AtomicLong(-1);
            AtomicLong leaderElectedMs = new AtomicLong(-1);
            AtomicInteger leaderBeforeFailover = new AtomicInteger(-1);
            AtomicInteger recoveredLeaderId = new AtomicInteger(-1);
            AtomicBoolean waitingForRecoveryAck = new AtomicBoolean(false);
            AtomicLong lastAckMs = new AtomicLong(-1);
            AtomicInteger lastAckId = new AtomicInteger(-1);
            AtomicLong lastAckBeforeFailoverMs = new AtomicLong(-1);
            AtomicInteger lastAckBeforeFailoverId = new AtomicInteger(-1);

            while(true) {

                 // Monitor the Leader using AdminClient (Forces a network check)
                try {
                    Collection<Node> clusterNodes = adminClient.describeCluster().nodes().get();
                    String currentClusterNodes = clusterNodes.stream()
                            .sorted(Comparator.comparingInt(Node::id))
                            .map(node -> node.id() + "@" + node.host() + ":" + node.port())
                            .reduce((a, b) -> a + ", " + b)
                            .orElse("");
                    if (!currentClusterNodes.equals(previousClusterNodes)) {
                        System.out.println("Cluster nodes: [" + currentClusterNodes + "]");
                        previousClusterNodes = currentClusterNodes;
                    }

                    Map<String, org.apache.kafka.clients.admin.TopicDescription> topicDescription = 
                        adminClient.describeTopics(Collections.singleton(topic)).all().get();
                    
                    org.apache.kafka.clients.admin.TopicDescription desc = topicDescription.get(topic);
                    org.apache.kafka.common.TopicPartitionInfo partitionInfo = desc.partitions().get(0);
                    Node leader = partitionInfo.leader();
                    List<Node> isr = partitionInfo.isr();
                    int leaderId = (leader != null) ? leader.id() : -1;
                    long nowMs = System.currentTimeMillis();

                    if (previousLeaderId != -1 && leaderId != -1
                            && leaderId != previousLeaderId && failoverStartMs.get() < 0) {
                        failoverStartMs.set(nowMs);
                        leaderBeforeFailover.set(previousLeaderId);
                        waitingForRecoveryAck.set(true);
                        leaderElectedMs.set(nowMs);
                        recoveredLeaderId.set(leaderId);
                        lastAckBeforeFailoverMs.set(lastAckMs.get());
                        lastAckBeforeFailoverId.set(lastAckId.get());
                        long lastAckToFailoverStartMs = (lastAckBeforeFailoverMs.get() >= 0)
                                ? nowMs - lastAckBeforeFailoverMs.get() : -1;
                        System.out.println("FAILOVER_STARTED oldLeader=" + previousLeaderId
                                + " reason=leader_switch at=" + formatTimestamp(nowMs)
                                + " lastAckId=" + lastAckBeforeFailoverId.get()
                                + " lastAckAt=" + formatTimestampIfPresent(lastAckBeforeFailoverMs.get())
                                + " lastAckToFailoverStartMs=" + lastAckToFailoverStartMs);
                        long lastAckToLeaderElectedMs = (lastAckBeforeFailoverMs.get() >= 0)
                                ? nowMs - lastAckBeforeFailoverMs.get() : -1;
                        System.out.println("LEADER_ELECTED oldLeader=" + previousLeaderId
                                + " newLeader=" + leaderId
                                + " electionMs=0"
                                + " lastAckToLeaderElectedMs=" + lastAckToLeaderElectedMs);
                    }
                    if (previousLeaderId != -1 && leaderId == -1 && failoverStartMs.get() < 0) {
                        failoverStartMs.set(nowMs);
                        leaderBeforeFailover.set(previousLeaderId);
                        waitingForRecoveryAck.set(true);
                        leaderElectedMs.set(-1);
                        recoveredLeaderId.set(-1);
                        lastAckBeforeFailoverMs.set(lastAckMs.get());
                        lastAckBeforeFailoverId.set(lastAckId.get());
                        long lastAckToFailoverStartMs = (lastAckBeforeFailoverMs.get() >= 0)
                                ? nowMs - lastAckBeforeFailoverMs.get() : -1;
                        System.out.println("FAILOVER_STARTED oldLeader=" + previousLeaderId
                                + " at=" + formatTimestamp(nowMs)
                                + " lastAckId=" + lastAckBeforeFailoverId.get()
                                + " lastAckAt=" + formatTimestampIfPresent(lastAckBeforeFailoverMs.get())
                                + " lastAckToFailoverStartMs=" + lastAckToFailoverStartMs);
                    }
                    if (failoverStartMs.get() >= 0 && leaderId != -1 && leaderId != leaderBeforeFailover.get()
                            && leaderElectedMs.get() < 0) {
                        leaderElectedMs.set(nowMs);
                        recoveredLeaderId.set(leaderId);
                        long lastAckToLeaderElectedMs = (lastAckBeforeFailoverMs.get() >= 0)
                                ? nowMs - lastAckBeforeFailoverMs.get() : -1;
                        System.out.println("LEADER_ELECTED oldLeader=" + leaderBeforeFailover.get()
                                + " newLeader=" + leaderId
                                + " electionMs=" + (nowMs - failoverStartMs.get())
                                + " lastAckToLeaderElectedMs=" + lastAckToLeaderElectedMs);
                    }

                    // Convert List<Node> to int[] for printing
                    int[] inSyncReplicas = isr.stream().mapToInt(Node::id).toArray();
                    String currentIsrString = Arrays.toString(inSyncReplicas);

                    // Check if Leader OR ISR has changed
                    if ((leader != null && leader.id() != previousLeaderId) || !currentIsrString.equals(previousIsrString)) {
                         
                         String leaderHost = (leader != null) ? leader.host() : "unknown";
                         int leaderPort = (leader != null) ? leader.port() : -1;
                         System.out.println("LEADER_ISR leader=" + leaderId
                                 + " host=" + leaderHost
                                 + " port=" + leaderPort
                                 + " isr=" + currentIsrString);
                         
                         previousLeaderId = leaderId;
                         previousIsrString = currentIsrString;

                    } else if (leader == Node.noNode()) { 
                         System.out.println("NO LEADER currently available!");
                         previousLeaderId = -1;
                    }
                } catch (Exception e) {
                    if (previousLeaderId != -1 && failoverStartMs.get() < 0) {
                        long nowMs = System.currentTimeMillis();
                        failoverStartMs.set(nowMs);
                        leaderBeforeFailover.set(previousLeaderId);
                        waitingForRecoveryAck.set(true);
                        leaderElectedMs.set(-1);
                        recoveredLeaderId.set(-1);
                        lastAckBeforeFailoverMs.set(lastAckMs.get());
                        lastAckBeforeFailoverId.set(lastAckId.get());
                        long lastAckToFailoverStartMs = (lastAckBeforeFailoverMs.get() >= 0)
                                ? nowMs - lastAckBeforeFailoverMs.get() : -1;
                        System.out.println("FAILOVER_STARTED oldLeader=" + previousLeaderId
                                + " at=" + formatTimestamp(nowMs)
                                + " lastAckId=" + lastAckBeforeFailoverId.get()
                                + " lastAckAt=" + formatTimestampIfPresent(lastAckBeforeFailoverMs.get())
                                + " lastAckToFailoverStartMs=" + lastAckToFailoverStartMs);
                    }
                    System.out.println("Cluster is unreachable or Leader is down.");
                    previousLeaderId = -1;
                }

                // sleep for a random time interval between 500 ms and 5000 ms
                try {
//                    Thread.sleep(getRandomNumber(500, 5000));
                    Thread.sleep(150);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }

                // generate a random click event using epoch milliseconds for readable timestamps
                long eventTimestampMs = System.currentTimeMillis();
                Clicks clickEvent = new Clicks(counter, eventTimestampMs, getRandomNumber(0, 1920), getRandomNumber(0, 1080), "EL"+getRandomNumber(1, 20));

                final int eventId = counter;
                producer.send(new ProducerRecord<>(
                        topic,
                        clickEvent
                ), (metadata, exception) -> {
                    if (exception != null) {
                        System.out.println("SEND FAILED id=" + eventId + " err="
                                + exception.getClass().getSimpleName() + " " + exception.getMessage());
                    } else {
                        long ackNowMs = System.currentTimeMillis();
                        System.out.println("ACKED id=" + eventId + " partition="
                                + metadata.partition() + " offset=" + metadata.offset());
                        if (waitingForRecoveryAck.get()) {
                            long startedAt = failoverStartMs.get();
                            long electedAt = leaderElectedMs.get();
                            long totalRecoveryMs = (startedAt >= 0) ? ackNowMs - startedAt : -1;
                            long electionMs = (startedAt >= 0 && electedAt >= 0) ? electedAt - startedAt : -1;
                            long postElectionToAckMs = (electedAt >= 0) ? ackNowMs - electedAt : -1;
                            long lastAckToLeaderElectedMs = (lastAckBeforeFailoverMs.get() >= 0 && electedAt >= 0)
                                    ? electedAt - lastAckBeforeFailoverMs.get() : -1;
                            long lastAckToRecoveredAckMs = (lastAckBeforeFailoverMs.get() >= 0)
                                    ? ackNowMs - lastAckBeforeFailoverMs.get() : -1;
                            System.out.println("FAILOVER_RECOVERED oldLeader=" + leaderBeforeFailover.get()
                                    + " newLeader=" + recoveredLeaderId.get()
                                    + " electionMs=" + electionMs
                                    + " firstAckAfterRecoveryMs=" + totalRecoveryMs
                                    + " postElectionToAckMs=" + postElectionToAckMs
                                    + " lastAckBeforeFailoverId=" + lastAckBeforeFailoverId.get()
                                    + " lastAckBeforeFailoverAt=" + formatTimestampIfPresent(lastAckBeforeFailoverMs.get())
                                    + " lastAckToLeaderElectedMs=" + lastAckToLeaderElectedMs
                                    + " lastAckToFirstRecoveredAckMs=" + lastAckToRecoveredAckMs
                                    + " recoveredAt=" + formatTimestamp(ackNowMs)
                                    + " firstAckId=" + eventId);
                            waitingForRecoveryAck.set(false);
                            failoverStartMs.set(-1);
                            leaderElectedMs.set(-1);
                            leaderBeforeFailover.set(-1);
                            recoveredLeaderId.set(-1);
                            lastAckBeforeFailoverMs.set(-1);
                            lastAckBeforeFailoverId.set(-1);
                        }
                        lastAckMs.set(ackNowMs);
                        lastAckId.set(eventId);
                    }
                });

                // print to console in a log-friendly format
                System.out.println("CLICK_EVENT_QUEUED id=" + eventId
                        + " at=" + formatTimestamp(eventTimestampMs)
                        + " payload=" + clickEvent.toString());

                // increment counter i.e., eventID
                counter++;

            }

        } catch (Throwable throwable) {
            throwable.printStackTrace();
        } finally {
            producer.close();
        }


    }


    /*
    Generate a random nunber
    */
    private static int getRandomNumber(int min, int max) {
        return (int) ((Math.random() * (max - min)) + min);
    }

    private static String formatTimestamp(long epochMillis) {
        return Instant.ofEpochMilli(epochMillis)
                .atZone(ZoneId.systemDefault())
                .format(TS_FORMATTER);
    }

    private static String formatTimestampIfPresent(long epochMillis) {
        return epochMillis >= 0 ? formatTimestamp(epochMillis) : "unknown";
    }

    /*
    Create topic
     */
    private static void createTopic(String topicName, int numPartitions, int numReplicates, Properties properties) throws Exception {

        AdminClient admin = AdminClient.create(properties);

        //checking if topic already exists
        boolean alreadyExists = admin.listTopics().names().get().stream()
                .anyMatch(existingTopicName -> existingTopicName.equals(topicName));
        if (alreadyExists) {
            System.out.printf("topic already exits: %s%n", topicName);
        } else {
            //creating new topic
            System.out.printf("creating topic: %s%n", topicName);
            NewTopic newTopic = new NewTopic(topicName, numPartitions, (short) numReplicates); // 
            admin.createTopics(Collections.singleton(newTopic)).all().get();
        }
    }

    /*
    Delete topic
     */
    private static void deleteTopic(String topicName, Properties properties) {
        try (AdminClient client = AdminClient.create(properties)) {
            DeleteTopicsResult deleteTopicsResult = client.deleteTopics(Collections.singleton(topicName));
            while (!deleteTopicsResult.all().isDone()) {
                // Wait for future task to complete
            }
        }
    }

}
