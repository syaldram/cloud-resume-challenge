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

    logging.info(event)
    try:
        response = table.get_item(Key={"CounterID": '1'})
        logging.info(f"getting dynamodb items ${response}")
        views = int(response['Item']['views'])
        logging.info(f"The total number of views in dynamodb: ${views}")
    except ClientError as e:
        logging.error(e)
        return {
            'statusCode': 500,
            'body': json.dumps('An error occurred while retrieving the viewer count.')
        }
    return {
        'statusCode': 200,
        'body': json.dumps(views)
    }

