package org.treasurelogpose.datastream;

import org.apache.flink.api.common.typeinfo.Types;
import org.apache.flink.api.java.tuple.Tuple2;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.configuration.RestOptions;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.treasurelogpose.datastream.operations.LineSplitter;

/**
 * Word Count example using Flink's DataStream API.
 * This example counts the occurrences of each word in the input stream.'
 */
public class WordCount {

    public static void main(String[] args) throws Exception {

        Configuration conf = new Configuration();
        conf.set(RestOptions.PORT, 8082);
        try (StreamExecutionEnvironment env = StreamExecutionEnvironment.createLocalEnvironmentWithWebUI(conf)) {
            env.fromData("Hello World Hello Flink")
                    // Split lines into words
                    .flatMap(new LineSplitter())
                    // Add 1 for each word
                    .map(word -> Tuple2.of(word, 1))
                    .returns(Types.TUPLE(Types.STRING, Types.INT)) // Type hint. Without this, Flink will throw InvalidTypesException
                    // Group by word and sum occurrences
                    .keyBy(tuple -> tuple.f0)
                    // Reduce by adding the counts of each word
                    .reduce((a, b) -> Tuple2.of(a.f0, a.f1 + b.f1))
                    .print();

            env.execute("Word Count Example");
        }

    }

}

