from riotwatcher import TftWatcher
import boto3
import csv
from datetime import datetime
from io import StringIO
import os
from datetime import datetime
from algoliasearch.search_client import SearchClient

RIOT_REGION = 'euw1'
RIOT_API_KEY = os.environ['RIOT_API_KEY']
ALGOLIA_APPID = os.environ['ALGOLIA_APPID']
ALGOLIA_SECRET_KEY = os.environ['ALGOLIA_SECRET_KEY']
AWS_S3_BUCKET = os.environ['AWS_S3_BUCKET']

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
    file_key = 'db/summoners/all_summoners_' + datetime.now().strftime('%Y%m%d') + '.csv'
    csv_file.seek(0)
    bucket.put_object(Body=csv_file.read(), Key=file_key)

    return None
