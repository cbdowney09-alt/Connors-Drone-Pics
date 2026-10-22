"""Extract every US address from Overture into one folder per state (st=XX/*.parquet).
Usage: python extract_us.py   (writes ./us; needs pip install duckdb)"""
import duckdb, time
con = duckdb.connect()
con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2'; SET threads=8; SET preserve_insertion_order=false;")
src = "s3://overturemaps-us-west-2/release/2026-09-23.1/theme=addresses/type=address/*"
t=time.time()
con.execute(f"""COPY (
  SELECT address_levels[1].value AS st, bbox.ymin AS lat, bbox.xmin AS lng, number, street, postcode, postal_city,
         address_levels[2].value AS city
  FROM read_parquet('{src}', hive_partitioning=1)
  WHERE country = 'US' AND bbox.xmin BETWEEN -180 AND -60 AND bbox.ymin BETWEEN 15 AND 72
) TO 'us' (FORMAT parquet, COMPRESSION zstd, PARTITION_BY (st), OVERWRITE_OR_IGNORE)""")
print('export', round(time.time()-t), 's', flush=True)
print(con.execute("SELECT st, count(*) FROM read_parquet('us/*/*.parquet', hive_partitioning=1) GROUP BY st ORDER BY 2 DESC").fetchall(), flush=True)
