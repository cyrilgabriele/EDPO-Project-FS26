# lab03Part1-kafka-spring

In this lab, you will see how to use the **Spring Boot-Kafka integration** to send and consume message from a Spring Boot application via Kafka.

This lab is adapted from [here](https://github.com/rahul-ghadge/spring-boot-kafka).

This is a Spring Boot Kafka application with multiple Producers and multiple Consumers for String data and JSON objects.

The project explains how to **publish** messages on a Kafka topic and how to **consume** a message from a Kafka topic. 

The messages can either be Strings or JSON Objects. There are two publishers, one for String data and for JSON objects.

For those two publishers, two `KafkaTemplate`s are used. 

To consume those messages and objects two `@KafkaListner` consumers are used.

## Running the Lab

The root folder has the [docker-compose.yml](docker-compose.yml) file with the Kafka configuration from labs 01 and 02.

Simply run 
  ```
  $ docker compose up
  ```
to start Kafka.

You can run the main java file [SpringBootKafkaApplication.java](/src/main/java/ch/unisg/kafka/spring/SpringBootKafkaApplication.java) of the Spring Boot project directly via your IDE
or you can run the project via Maven, e.g., by running
  ```
  $ mvn spring-boot:run
  ```
on the Terminal.

### Code Snippets

1. #### Maven Dependencies
   Dependencies for Kafka in **pom.xml**.
    ```
    <dependency>
        <groupId>org.springframework.kafka</groupId>
        <artifactId>spring-kafka</artifactId>
    </dependency>
    ```

2. #### Properties file
   Some properties are in the **application.yml** file, e.g., bootstrap servers, group id and topics.  
   Here we have two topics to publish and consume data.
   > message-topic (for string data)  
   superhero-topic (for SuperHero objects)

   **src/main/resources/application.yml**
     ```
     spring:
       kafka:
         consumer:
           bootstrap-servers: localhost:9092
           group-id: group_id
   
         producer:
           bootstrap-servers: localhost:9092
   
         topic: message-topic
         superhero-topic: superhero-topic  
     ```

3. #### Model class
   This is the model class of a SuperHero which we will publish to a Kafka topic using `KafkaTemplate` and consume using `@KafkaListener` from the same topic.  
   **ch.unisg.kafka.spring.model.SuperHero.java**
    ```
    public class SuperHero implements Serializable {
    
        private String name;
        private String superName;
        private String profession;
        private int age;
        private boolean canFly;
   
        // Constructor, Getter and Setter
    }
    ```

4. #### Kafka Configuration
   The Kafka Producer configuration is in the **ch.unisg.kafka.spring.config.KafkaProducerConfig.java** class.  
   This class is marked with the `@Configuration` annotation. For the JSON producer we have to set the value serializer property to `JsonSerializer.class`
   and pass that factory to the KafkaTemplate.  
   For the String producer we have to set the value serializer property to `StringSerializer.class` and pass that factory to a new KafkaTemplate.
    - JSON Producer configuration
      ```
      configProps.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
      configProps.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class);
      ```
      ```
      @Bean
      public <T> KafkaTemplate<String, T> kafkaTemplate() {
          return new KafkaTemplate<>(producerFactory());
      }  
      ``` 

    - String Producer configuration
      ```
      configProps.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
      configProps.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
      ```
      ```
      @Bean
      public KafkaTemplate<String, String> kafkaStringTemplate() {
          return new KafkaTemplate<>(producerStringFactory());
      }
      ```

   The Kafka Consumer configuration is in the **ch.unisg.kafka.spring.config.KafkaConsumerConfig.java** class.  
   This class is marked with annotations `@Configuration` and `@EnableKafka` (mandatory to consume messages in config class or main class).
   For the JSON consumer we have to set value deserializer property to `JsonDeserializer.class` and pass that factory to ConsumerFactory.  
   For the String consumer we have to set value deserializer property to `StringDeserializer.class` and pass that factory to a new ConsumerFactory.
    - JSON Consumer configuration
      ```
      @Bean
      public ConsumerFactory<String, SuperHero> consumerFactory() {
         Map<String, Object> config = new HashMap<>();
     
         config.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
         config.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
         config.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
         config.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);
         config.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
         config.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, JsonDeserializer.class);
     
         return new DefaultKafkaConsumerFactory<>(config, new StringDeserializer(), new JsonDeserializer<>(SuperHero.class));
      }
      
      @Bean
      public <T> ConcurrentKafkaListenerContainerFactory<?, ?> kafkaListenerJsonFactory() {
         ConcurrentKafkaListenerContainerFactory<String, SuperHero> factory = new ConcurrentKafkaListenerContainerFactory<>();
         factory.setConsumerFactory(consumerFactory());
         factory.setMessageConverter(new StringJsonMessageConverter());
         factory.setBatchListener(true);
         return factory;
      }     

    - String Consumer configuration
      ``` 
      @Bean
      public ConsumerFactory<String, String> stringConsumerFactory() {
         Map<String, Object> config = new HashMap<>();
   
         config.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
         config.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
         config.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
         config.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);
         config.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
         config.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
   
         return new DefaultKafkaConsumerFactory<>(config, new StringDeserializer(), new StringDeserializer());
      }
   
      @Bean
      public ConcurrentKafkaListenerContainerFactory<String, String> kafkaListenerStringFactory() {
         ConcurrentKafkaListenerContainerFactory<String, String> factory = new ConcurrentKafkaListenerContainerFactory<>();
         factory.setConsumerFactory(stringConsumerFactory());
         factory.setBatchListener(true);
         return factory;
      }

5. #### Publishing Messages to a Kafka Topic
   In the **ch.unisg.kafka.spring.service.ProducerService.java** class both String and JSON `KafkaTemplate`s are autowired.
   Using the send() method we can publish messages (records) to kafka topics.
    - Publishing a Message containing a value as JSON Object
        ```
        @Autowired
        private KafkaTemplate<String, T> kafkaTemplateSuperHero;
       
        public void sendSuperHeroMessage(T superHero) {
            logger.info("#### -> Publishing SuperHero :: {}", superHero);
            kafkaTemplateSuperHero.send(superHeroTopic, superHero);
        }
        ```
    - Publishing a Message containing a value as String
        ```
        @Autowired
        private KafkaTemplate<String, String> kafkaTemplate;
        
        public void sendMessage(String message) {
            logger.info("#### -> Publishing message -> {}", message);
            kafkaTemplate.send(topic, message);
        }
        ```

6. #### Consuming Messages from a Kafka Topic
   In the **ch.unisg.kafka.spring.service.ConsumerService.java** class, we are consuming messages from topics using the `@KafkaListener` annotation.
   We are binding the consumer factory from the **KafkaConsumerConfig.java** class to the **containerFactory** in the KafkaListener.
    ```
    // String Consumer
    @KafkaListener(topics = {"${spring.kafka.topic}"}, containerFactory = "kafkaListenerStringFactory", groupId = "group_id")
    public void consumeMessage(String message) {
        logger.info("**** -> Consumed message -> {}", message);
    }        
    
    // Object Consumer   
    @KafkaListener(topics = {"${spring.kafka.superhero-topic}"}, containerFactory = "kafkaListenerJsonFactory", groupId = "group_id")
    public void consumeSuperHero(SuperHero superHero) {
        logger.info("**** -> Consumed Super Hero :: {}", superHero);
    }
    ```

### API Endpoints

> **GET Mapping** http://localhost:8080/kafka/publish?message=hello

> **POST Mapping** http://localhost:8080/kafka/publish

Request Body
  ```
    {
        "name": "Tony",
        "superName": "Iron Man",
        "profession": "Business",
        "age": 50,
        "canFly": true
    }
  ```

### Console Outputs
```
2023-02-08 14:42:16.501  INFO 27812 --- [nio-8080-exec-2] c.u.k.spring.service.ProducerService     : #### -> Publishing message -> Hello World
2023-02-08 14:42:16.663  INFO 27812 --- [ntainer#0-0-C-1] c.u.k.spring.service.ConsumerService     : **** -> Consumed message -> Hello World
2023-02-08 14:43:16.568  INFO 27812 --- [nio-8080-exec-3] c.u.k.spring.service.ProducerService     : #### -> Publishing SuperHero :: SuperHero [name=Tony, superName=Iron Man, profession=Business, age=50, canFly=true]
2023-02-08 14:43:16.600  INFO 27812 --- [ntainer#1-0-C-1] c.u.k.spring.service.ConsumerService     : **** -> Consumed Super Hero :: SuperHero [name=Tony, superName=Iron Man, profession=Business, age=50, canFly=true]
```