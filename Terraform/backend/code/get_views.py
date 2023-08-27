import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

LOGLEVEL = os.environ.get('LOGLEVEL', 'INFO').upper()
logging_format = '[%(levelname)s] %(filename)s:%(lineno)d %(message)s'
logging.basicConfig(
    level=LOGLEVEL,
    format=logging_format,
)

logging.getLogger('botocore').setLevel(logging.ERROR)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('crc-counter')

def lambda_handler(event, context):

    try:
        response = table.get_item(Key={"CounterID": '1'})
        views = response['Item']['views']
        logging.info(f'Current total view count is ${views}.')
    except ClientError as e:
        logging.error(e)
    return views

