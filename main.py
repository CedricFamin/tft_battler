from riotwatcher import TftWatcher

import boto3
import csv
from datetime import datetime
from io import StringIO
import os

from algoliasearch.search_client import SearchClient


RIOT_REGION = 'euw1'
RIOT_API_KEY = os.environ['RIOT_API_KEY']
ALGOLIA_APPID = os.environ['ALGOLIA_APPID']
ALGOLIA_SECRET_KEY = os.environ['ALGOLIA_SECRET_KEY']
AWS_S3_BUCKET = os.environ['S3_BUCKET']

def order_fields(d, fields):
    return [d.get(field, '') for field in fields]

def init_riot_watcher():
    api_key = RIOT_API_KEY
    watcher = TftWatcher(api_key)
    return watcher

def feed_dim_challengers(event = None, context = None): 
    
    watcher = init_riot_watcher()
    challengers = watcher.league.challenger(RIOT_REGION)

    FIELDS = [
    'name'
    , 'id'
    , 'puuid'
    , 'accountid'
    , 'profileIconId'
    , 'revisionDate'
    , 'summonerLevel'
]
    csv_file = StringIO()
    csv_writer = csv.writer(csv_file, delimiter='\t')
    csv_writer.writerow(FIELDS + ['date'])

    current_date = datetime.now().strftime('%Y%m%d')

    algolia_entries = []
    for challenger in challengers['entries']:
        print(challenger["summonerName"])
        profile = watcher.summoner.by_id(RIOT_REGION, challenger['summonerId'])
        line_raw = order_fields(profile, FIELDS)
        csv_writer.writerow(line_raw + [current_date])
        profile['objectID'] = profile['id']
        algolia_entries.append(profile)

    client = SearchClient.create(ALGOLIA_APPID, ALGOLIA_SECRET_KEY)
    index = client.init_index("tft_battler")
    index.save_objects(algolia_entries).wait()

    s3 = boto3.resource('s3')
    bucket = s3.Bucket(AWS_S3_BUCKET)
    file_key = 'dim/summoners/all_summoners_' + datetime.now().strftime('%Y%m%d') + '.csv'
    csv_file.seek(0)
    bucket.put_object(Body=csv_file.read(), Key=file_key)

    

    return None

from datetime import timedelta
from datetime import date
from datetime import datetime
from botocore.config import Config

def get_all_challengers_puuid():

    client = boto3.client('athena', config=Config(region_name='eu-west-3'))

    executions = client.list_query_executions(WorkGroup='TFT_Battler')
    puuids = []
    for execution in executions['QueryExecutionIds']:
        result = client.get_query_results(QueryExecutionId=execution)
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
    file_key = f"fact/match_placement/year={start_date.year}/month={start_date.month:02d}/day={start_date.day:02d}/" + start_date.strftime('%Y%m%d') + '.csv'
    csv_file.seek(0)
    bucket.put_object(Body=csv_file.read(), Key=file_key)
    print("end")
