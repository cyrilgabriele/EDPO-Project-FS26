package ch.unisg.cryptoflow.userservice;

import com.github.lalyos.jfiglet.FigletFont;
import org.springframework.boot.SpringBootVersion;
import org.springframework.core.SpringVersion;

import java.io.IOException;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.Locale;
import java.util.Objects;

public class Banner {
    private Banner() {
    }

    private static final String JAVA = Runtime.version().toString() + " - " + System.getProperty("java.vendor");
    private static final InetAddress LOCALHOST = getLocalhost();
    private static final long MEGABYTE = 1024L * 1024L;
    private static final Runtime RUNTIME = Runtime.getRuntime();

    private static String getFiglet(String text){
        try {
            return FigletFont.convertOneLine(text);
        } catch (IOException e) {
            return text;
        }
    }

    public static final String TEXT = """
            $figlet
            (c) Ioannis Theodosiadis, Cyril Gabriele, MCS at University of St. Gallen
            Version             1.0.0
            Spring Boot         $springBoot
            Spring Framework    $spring
            Java                $java
            Operating System    $os
            Machine             $computer
            Username            $username
            IP-Address          $ip
            JVM Locale          $locale
            Heap: Size          $heapSize MiB
            Heap: Free          $heapFree MiB
            """
            .replace("$figlet", getFiglet("User-Service"))
            .replace("$springBoot", SpringBootVersion.getVersion())
            .replace("$spring", Objects.requireNonNull(SpringVersion.getVersion()))
            .replace("$java", JAVA)
            .replace("$os", System.getProperty("os.name"))
            .replace("$computer", LOCALHOST.getHostName())
            .replace("$username", System.getProperty("user.name"))
            .replace("$ip", LOCALHOST.getHostAddress())
            .replace("$locale", Locale.getDefault().toString())
            .replace("$heapSize", String.valueOf(RUNTIME.totalMemory() / MEGABYTE))
            .replace("$heapFree", String.valueOf(RUNTIME.freeMemory() / MEGABYTE));

    private static InetAddress getLocalhost() {
        try {
            return InetAddress.getLocalHost();
        } catch (final UnknownHostException ex) {
            throw new IllegalStateException(ex);
        }
    }
}
