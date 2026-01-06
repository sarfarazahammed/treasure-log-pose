CREATE TABLE server_logs
(
    client_ip       STRING,
    client_identity STRING,
    userid          STRING,
    user_agent      STRING,
    log_time        TIMESTAMP(3),
    request_line    STRING,
    status_code     STRING,
    size            INT,
    WATERMARK FOR log_time AS log_time - INTERVAL '5' SECOND
) WITH (
      'connector' = 'faker',
      'rows-per-second' = '50',
      'fields.client_ip.expression' = '#{Internet.publicIpV4Address}',
      'fields.client_identity.expression' = '-',
      'fields.userid.expression' = '-',
      'fields.user_agent.expression' = '#{Internet.userAgent}',
      'fields.log_time.expression' = '#{date.past ''15'',''5'',''SECONDS''}',
      'fields.request_line.expression' = '#{regexify ''(GET|POST|PUT|PATCH){1}''} #{regexify ''(/search\\.html|/login\\.html|/prod\\.html|/cart\\.html|/order\\.html){1}''} #{regexify ''(HTTP/1\\.1|HTTP/2|HTTP/1\\.0){1}''}',
      'fields.status_code.expression' = '#{regexify ''(200|201|204|400|401|403|301|500|502|503){1}''}',
      'fields.size.expression' = '#{number.numberBetween ''100'',''10000000''}'
      );

CREATE
CATALOG paimon_minio WITH (
  'type' = 'paimon',
  'warehouse' = 's3://paimon-warehouse/',
  's3.endpoint' = 'http://minio:9000',
  's3.access-key' = 'admin',
  's3.secret-key' = 'rootpass123',
  's3.path.style.access' = 'true'
);

CREATE VIEW parsed_logs AS
SELECT client_ip,
       client_identity,
       NULLIF(userid, '-')                                      AS userid,
       user_agent,
       log_time,
       request_line,
       REGEXP_EXTRACT(request_line, '^(GET|POST|PUT|PATCH)', 1) AS http_method,
       REGEXP_EXTRACT(request_line, '\\s([^\\s]+)\\sHTTP', 1)   AS path,
       CAST(status_code AS INT)                                 AS status_code,
        size
        FROM server_logs;


CREATE TABLE ip_geo
(
    start_ip     STRING,
    end_ip       STRING,
    join_key     STRING,
    city         STRING,
    region       STRING,
    region_name  STRING,
    country      STRING,
    country_name STRING,
    latitude DOUBLE,
    longitude DOUBLE,
    postal_code  STRING,
    timezone     STRING,
    geoname_id   BIGINT,
    radius       INT
) WITH (
      'connector' = 'filesystem',
      'path' = 'file:///opt/flink/db_data/ip_geo.csv',
      'format' = 'csv',
      'csv.field-delimiter' = ',',
      'csv.ignore-parse-errors' = 'true',
      'csv.allow-comments' = 'false',
      'csv.disable-quote-character' = 'false',
      'csv.ignore-first-line' = 'true' -- skip the header row
      );

CREATE VIEW ip_country_with_prefix AS
SELECT country,
       REGEXP_EXTRACT(start_ip, '^(\d+\.\d+\.\d+)', 1) AS ip_prefix
FROM ip_geo;

CREATE VIEW enriched AS
SELECT p.*,
       COALESCE(g.country, 'UNKNOWN') AS country
FROM parsed_logs AS p
         LEFT JOIN ip_country_with_prefix AS g
                   ON REGEXP_EXTRACT(p.client_ip, '^(\d+\.\d+\.\d+)', 1) = g.ip_prefix;

-- 4) Deduplicate events (event key)
CREATE VIEW deduped AS
SELECT *
FROM (SELECT *,
             ROW_NUMBER() OVER (
      PARTITION BY client_ip, log_time, request_line
      ORDER BY log_time
    ) AS rn
      FROM enriched)
WHERE rn = 1;

SET 'execution.checkpointing.interval' = '10s';
SET 'execution.checkpointing.enabled' = 'true';

-- 5) Paimon sink: enriched events partitioned by DATE(log_time)
CREATE TABLE `paimon_minio`.`default`.`paimon_enriched`
(
    client_ip       STRING,
    client_identity STRING,
    userid          STRING,
    user_agent      STRING,
    log_time        TIMESTAMP(3),
    request_line    STRING,
    http_method     STRING,
    path            STRING,
    status_code     INT,
    size            INT,
    country         STRING,
    dt              STRING
) PARTITIONED BY (dt)
WITH (
  'connector' = 'paimon',
  'file.format' = 'parquet'
);

INSERT INTO `paimon_minio`.`default`.`paimon_enriched`
SELECT client_ip,
       client_identity,
       userid,
       user_agent,
       log_time,
       request_line,
       http_method,
       path,
       status_code, size, country, DATE_FORMAT(log_time, 'yyyy-MM-dd') AS dt
FROM deduped;

-- 6) Sessionization (Paimon sink): session table partitioned by session_start date
CREATE TABLE `paimon_minio`.`default`.`paimon_sessions`
(
    session_key     STRING,
    session_start   TIMESTAMP(3),
    session_end     TIMESTAMP(3),
    events          BIGINT,
    size_in_bytes   BIGINT,
    countries       MULTISET<STRING>,
    last_event_time TIMESTAMP(3),
    dt              DATE
) PARTITIONED BY (dt)
WITH (
  'connector' = 'paimon',
  'file.format' = 'orc'
);

INSERT INTO `paimon_minio`.`default`.`paimon_sessions`
SELECT COALESCE(userid, client_ip)                                AS session_key,
       SESSION_START(log_time, INTERVAL '5' MINUTE)               AS session_start,
       SESSION_END(log_time, INTERVAL '5' MINUTE)                 AS session_end,
       COUNT(*)                                                   AS events,
       CAST(SUM(CAST(size AS BIGINT)) AS BIGINT)                  AS size_in_bytes,
       COLLECT(DISTINCT country)                                  AS countries,
       MAX(log_time)                                              AS last_event_time,
       CAST(SESSION_START(log_time, INTERVAL '5' MINUTE) AS DATE) AS dt
FROM deduped
GROUP BY
    SESSION (log_time, INTERVAL '5' MINUTE),
    COALESCE (userid, client_ip);

-- 7) Minute metrics (Paimon sink) partitioned by minute date
CREATE TABLE `paimon_minio`.`default`.`paimon_minute_metrics`
(
    minute_start   TIMESTAMP(3),
    minute_end     TIMESTAMP(3),
    total_requests BIGINT,
    total_bytes    BIGINT,
    success_2xx    BIGINT,
    redirect_3xx   BIGINT,
    client_err_4xx BIGINT,
    server_err_5xx BIGINT,
    dt             STRING,
    hr             STRING

) PARTITIONED BY (dt, hr)
WITH (
  'connector' = 'paimon',
  'file.format' = 'avro'
);

INSERT INTO `paimon_minio`.`default`.`paimon_minute_metrics`
SELECT TUMBLE_START(log_time, INTERVAL '1' MINUTE)                               AS minute_start,
       TUMBLE_END(log_time, INTERVAL '1' MINUTE)                                 AS minute_end,
       COUNT(*)                                                                  AS total_requests,
       SUM(size)                                                                 AS total_bytes,
       SUM(CASE WHEN status_code >= 200 AND status_code < 300 THEN 1 ELSE 0 END) AS success_2xx,
       SUM(CASE WHEN status_code >= 300 AND status_code < 400 THEN 1 ELSE 0 END) AS redirect_3xx,
       SUM(CASE WHEN status_code >= 400 AND status_code < 500 THEN 1 ELSE 0 END) AS client_err_4xx,
       SUM(CASE WHEN status_code >= 500 THEN 1 ELSE 0 END)                       AS server_err_5xx,
       DATE_FORMAT(TUMBLE_START(log_time, INTERVAL '1' MINUTE), 'yyyy-MM-dd')    AS dt,
       DATE_FORMAT(TUMBLE_START(log_time, INTERVAL '1' MINUTE), 'HH')            AS hr
FROM deduped
GROUP BY TUMBLE(log_time, INTERVAL '1' MINUTE);

-- 8) Alerts (Paimon sink) for high 5xx rate (sliding window)
CREATE TABLE `paimon_minio`.`default`.`paimon_alerts`
(
    window_start   TIMESTAMP(3),
    window_end     TIMESTAMP(3),
    total_requests BIGINT,
    server_err_5xx BIGINT,
    err5xx_rate DOUBLE,
    dt             STRING
) PARTITIONED BY (dt)
WITH (
  'connector' = 'paimon',
  'file.format' = 'orc'
);

INSERT INTO `paimon_minio`.`default`.`paimon_alerts`
SELECT window_start,
       window_end,
       total_requests,
       server_err_5xx,
       server_err_5xx * 1.0 / NULLIF(total_requests, 0) AS err5xx_rate,
       DATE_FORMAT(window_start, 'yyyy-MM-dd')          AS dt
FROM (SELECT HOP_START(log_time, INTERVAL '1' MINUTE, INTERVAL '10' MINUTE) AS window_start,
             HOP_END(log_time, INTERVAL '1' MINUTE, INTERVAL '10' MINUTE)   AS window_end,
             COUNT(*)                                                       AS total_requests,
             SUM(CASE WHEN status_code >= 500 THEN 1 ELSE 0 END)            AS server_err_5xx
      FROM deduped
      GROUP BY HOP(log_time, INTERVAL '1' MINUTE, INTERVAL '10' MINUTE))
WHERE server_err_5xx * 1.0 / NULLIF(total_requests, 0) > 0.05;

