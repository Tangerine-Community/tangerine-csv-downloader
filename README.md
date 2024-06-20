# Tangerine CSV Downloader

This script uses the Tangerine API to download a full set of CSV files from all groups and forms.
It is expected that this script is run on the host machine and not within a container. The CSV files are generated within the Tangerine container and then copied to the host machine.

## Set up

1. Clone the repository
2. Create the `.env` environment file: `cp env .env`
3. Fill in the values for the environment variables in the `.env` file
4. Run the script: `./download-csvs.sh`

## Running with Cron

Add the following to your crontab to run the script nightly:

```
# Fetch and parse CSV's from Tangerine server. 15 6 * * * www-data
14 6 * * * echo "Download Log: $(date)" > /home/ubuntu/download-csvs.nightly.log
15 6 * * * su -pc "cd /home/ubuntu/tangerine-csv-downloader && /home/ubuntu/tangerine-csv-downloader/download-csvs.sh" www-data  >> /home/ubuntu/download-csvs.nightly.log
# Clean up csvs older than 1 day
0 5 * * * find /home/ubuntu/tangerine/data/csv/  -type f -name '*' -mtime +1 -exec rm {} \;
```