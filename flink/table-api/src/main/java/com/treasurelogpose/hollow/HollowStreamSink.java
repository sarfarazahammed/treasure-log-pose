package com.treasurelogpose.hollow;

import com.netflix.hollow.api.consumer.HollowConsumer;
import com.netflix.hollow.api.producer.HollowProducer;
import com.netflix.hollow.api.producer.fs.HollowFilesystemAnnouncer;
import com.netflix.hollow.api.producer.fs.HollowFilesystemPublisher;
import com.treasurelogpose.hollow.model.MovieTest;
import org.apache.flink.api.common.functions.OpenContext;
import org.apache.flink.streaming.api.functions.sink.legacy.RichSinkFunction;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

public class HollowStreamSink extends RichSinkFunction<MovieTest> {
    private transient HollowProducer.Incremental producer;
    private transient List<MovieTest> buffer;
    private final String publishPath;
    private final int batchSize;

    public HollowStreamSink(String publishPath, int batchSize) {
        this.publishPath = publishPath;
        this.batchSize = batchSize;
    }

    @Override
    public void open(OpenContext openContext) throws Exception {
        File publishDir = new File(publishPath);
        if (!publishDir.exists()) publishDir.mkdirs();

        // 1. Initialize the Producer (Using Filesystem for this example)
        // TODO: swap with S3Publisher/S3Announcer
        HollowFilesystemAnnouncer announcer = new HollowFilesystemAnnouncer(publishDir.toPath());
        HollowFilesystemPublisher publisher = new HollowFilesystemPublisher(publishDir.toPath());
        producer = HollowProducer.withPublisher(publisher)
                .withAnnouncer(announcer)
                .buildIncremental();

        buffer = new ArrayList<>();
    }

    @Override
    public void invoke(MovieTest value, Context context) throws Exception {

        buffer.add(value);

        // 2. Trigger a Hollow Cycle when batch size is reached
        if (buffer.size() >= batchSize) {
            emitCycle();
        }
    }

    private void emitCycle() {
        if (buffer.isEmpty()) return;

        System.out.println("Hollow Sink: Starting publication cycle for " + buffer.size() + " records.");

        // 3. The runCycle method handles the delta/snapshot creation
        producer.runIncrementalCycle(state -> {
            for (MovieTest movieTest : buffer) {
                state.addOrModify(movieTest);
            }
        });

        buffer.clear();
    }

    @Override
    public void close() throws Exception {
        // Ensure remaining records are published before the job stops
        if (!buffer.isEmpty()) {
            emitCycle();
        }
    }
}

