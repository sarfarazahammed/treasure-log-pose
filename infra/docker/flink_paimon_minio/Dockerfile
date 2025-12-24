FROM flink:1.19.3-java17

# Download Paimon JARs
ARG PAIMON_VERSION=1.2.0
ARG FLINK_HADOOP_VERSION=2.8.3-10.0
ARG AWS_SDK_VERSION=2.39.6
ARG HADOOP_AWS_VERSION=3.3.6

# Download utility function
COPY download.sh /download.sh
RUN chmod +x /download.sh

# Define downloads as a simple list of URL and filename
RUN /download.sh \
    "https://repo1.maven.org/maven2/org/apache/paimon/paimon-flink-1.19/${PAIMON_VERSION}/paimon-flink-1.19-${PAIMON_VERSION}.jar" "paimon-flink-1.19-${PAIMON_VERSION}.jar" \
    "https://repo1.maven.org/maven2/org/apache/paimon/paimon-s3/${PAIMON_VERSION}/paimon-s3-${PAIMON_VERSION}.jar" "paimon-s3-${PAIMON_VERSION}.jar" \
    "https://repo1.maven.org/maven2/org/apache/flink/flink-shaded-hadoop-2-uber/2.8.3-10.0/flink-shaded-hadoop-2-uber-2.8.3-10.0.jar" "flink-shaded-hadoop-2-uber-2.8.3-10.0.jar" \
    "https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/${AWS_SDK_VERSION}/bundle-${AWS_SDK_VERSION}.jar" "aws-sdk-bundle-${AWS_SDK_VERSION}.jar" \
    "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_AWS_VERSION}/hadoop-aws-${HADOOP_AWS_VERSION}.jar" "hadoop-aws-${HADOOP_AWS_VERSION}.jar"


# Verify JARs were downloaded
RUN ls -la /opt/flink/lib/