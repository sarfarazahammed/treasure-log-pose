package org.treasurelogpose.datastream.operations;

import org.apache.flink.api.common.functions.FlatMapFunction;
import org.apache.flink.util.Collector;

public class LineSplitter implements FlatMapFunction<String, String> {
    @Override
    public void flatMap(String value, Collector<String> out) {
        // Split the line into words
        String[] words = value.split("\\s+");
        // Emit each word
        for (String word : words) {
            out.collect(word);
        }
    }
}
