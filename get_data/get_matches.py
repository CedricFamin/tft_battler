from riotwatcher import TftWatcher
import boto3
import csv
from datetime import datetime
from io import StringIO
import os
from datetime import timedelta
from datetime import date
from datetime import datetime
from botocore.config import Config

RIOT_REGION = 'euw1'
RIOT_API_KEY = os.environ['RIOT_API_KEY']
AWS_S3_BUCKET = os.environ['AWS_S3_BUCKET']
AWS_ATHENA_REGION = os.environ['AWS_ATHENA_REGION']

def order_fields(d, fields):
    return [d.get(field, '') for field in fields]

def init_riot_watcher():
    api_key = RIOT_API_KEY
    watcher = TftWatcher(api_key)
    return watcher

def get_all_challengers_puuid():

    client = boto3.client('athena', config=Config(region_name=AWS_ATHENA_REGION))

    executions = client.list_query_executions(WorkGroup='TFT_Battler')
    puuids = []
    for execution in executions['QueryExecutionIds']:
        response = client.get_query_execution(QueryExecutionId=execution)
        if response['QueryExecution']['Status']['State'] == 'SUCCEEDED':
            result = client.get_query_results(QueryExecutionId=execution)
            if len(result['ResultSet']['ResultSetMetadata']['ColumnInfo']) == 1 and result['ResultSet']['ResultSetMetadata']['ColumnInfo'][0]['Name'] == 'puuid':
                puuids = [row['Data'][0]['VarCharValue'] for row in result["ResultSet"]['Rows'][1:]]
                break
    return puuids

def feed_fact_placements(event = None, context = None):

    users = get_all_challengers_puuid()
    watcher = init_riot_watcher()
    end_date = date.today()
    start_date = end_date - timedelta(days=1)
    end_date = datetime(end_date.year, end_date.month, end_date.day)
    start_date = datetime(start_date.year, start_date.month, start_date.day)

    all_matches_ids = set()
    for user in users:
        matches = watcher.match.by_puuid(
            RIOT_REGION
            , user
            , start_time=int(datetime.timestamp(start_date))
            , end_time=int(datetime.timestamp(end_date))
            , count=100
        )
        all_matches_ids |= set(matches)

    match_results = [['matchid', 'puuid', 'placement']]
    for match_id in all_matches_ids:
        print(match_id)
        match = watcher.match.by_id(RIOT_REGION, match_id)
        match_results += [(match_id, participant['puuid'], participant['placement']) for participant in match['info']['participants']]

    csv_file = StringIO()
    csv_writer = csv.writer(csv_file, delimiter='\t')
    csv_writer.writerows(match_results)

    s3 = boto3.resource('s3')
    bucket = s3.Bucket(AWS_S3_BUCKET)
    file_key = f"db/match_placement/year={start_date.year}/month={start_date.month}/day={start_date.day}/" + start_date.strftime('%Y%m%d') + ".csv"
    csv_file.seek(0)
    bucket.put_object(Body=csv_file.read(), Key=file_key)
    print("end")