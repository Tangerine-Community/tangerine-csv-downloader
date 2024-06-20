#!/usr/bin/env node

const fs = require("fs");
const axios = require('axios')
const stream = require('stream')
const promisify = require('util').promisify
const unzipper = require('unzipper')
const util = require('util');
const readdir = util.promisify(fs.readdir);
const unlink = util.promisify(fs.unlink);
const fse = require('fs-extra')

// const CSV_FILES = '../../data/csv/'
const CSV_FILES = '../csv/'

if (process.argv[2] === '--help') {
  console.log('Usage:')
  console.log('  download-csvs  ')
  console.log('Examples:')
  console.log(`  download-csvs`)
  process.exit()
}

const params = { }

let ENV_PATH = "../.env"
let env

async function getUser1HttpInterface(username, password) {
  const url = env['tangerineURL'] + '/login';
  console.log('url: ' + url)
  const body = await axios.post(url, {
    username: username,
    password: password
  })
  console.log("body.")
  const token = body['data']['data']['token']
  let http = axios.create({
    headers: {
      authorization: token
    },
    baseUrl: 'http://localhost'
  })
  return http
}

const finished = promisify(stream.finished);

async function downloadFile(fileUrl, username, password, outputLocationPath) {
  let http
  try {
    console.log('downloadFile to: ' + outputLocationPath)
    http = await getUser1HttpInterface(username, password)
    console.log("Got http. again.")
  } catch (err) {
      console.log("err: " + err)
      console.log(err.stack) 
  }
  if (http) {
    console.log("Creating writer at " + outputLocationPath)
    const writer = fs.createWriteStream(outputLocationPath);
    return http({
      method: 'get',
      url: fileUrl,
      responseType: 'stream',
    }).catch(error => {
      console.log("error: " + error)
    }).then(async response => {
      try {
        console.log("Writing out file.")
        response.data.pipe(writer);
        return finished(writer); //this is a Promise
      } catch (err) {
        console.log("error: " + err)
      }
    })
  }
}

async function getStatusDoc(http, url) {
        try {
            //console.log('username: ' + username)
            csvStatus = (await http.get(url)).data
            // console.log("csvStatus: " + JSON.stringify(csvStatus))
            // console.log("got csvStatus; complete? " + csvStatus.complete)
            return csvStatus
        } catch (err) {
            console.log("err: " + err)
        }
    }

async function go(params) {
  try {
    const content = fs.readFileSync(ENV_PATH);
    const lines = content.toString().split(/\r?\n/)
    env = {};

    for(var line = 0; line < lines.length; line++){
        //console.log('line:' + lines[line])
        if (!lines[line].startsWith('#')) {
            const currentline = lines[line].split('=');
            let key = currentline[0]
            let value = currentline[1]
            // console.log("key: " + key + " value: " + value )
            if ((key !== 'undefined' || key !== '') && typeof value !== 'undefined') {
                env[key.trim().replace(/["]/g, "")] = value.trim().replace(/["]/g, "").replace(/['']/g, "").replace(';', '')
            }
        }
    }

    const username = env['tangerineLoginUser']
    const password = env['tangerineLoginPassword']
    const tangerineURL = env['tangerineURL']

    const dataSetIdentifier = Date.now()
    let http
    let csvStatus
    try {
        http = await getUser1HttpInterface(username, password)
        console.log("Got http.")
    } catch (err) {
        console.log("Login error: " + err)
        console.log(err.stack) 
    }

    //csvStatus = (await http.get(`/csv/timestamp.json`)).data
    try {
      csvStatus = (await http.get(`${tangerineURL}/api/create/csvDataSets/${dataSetIdentifier}`)).data
      console.log("csvStatus: " + JSON.stringify(csvStatus))
  } catch (err) {
      console.log("err: " + err)
  }
    //console.log("csvStatus: " + JSON.stringify(csvStatus))

    //let intervalId = await setTimeout(() => {console.log("this is the first message")}, 2000);
    // const wait = (timeToDelay) => new Promise((resolve) => setTimeout(getStatusDoc.bind(this, http), 2000));

    let csvStatusPath = `${tangerineURL}/csv/${dataSetIdentifier}.json`

    let complete = false

    csvStatus = await new Promise(resolve => {
      const interval = setInterval(async () => {
        let csvStatus = await getStatusDoc(http, csvStatusPath)
        if (csvStatus && csvStatus.complete) {
          resolve(csvStatus);
          clearInterval(interval);
        } else {
          console.log("Still processing data...")
        }
      }, 1000);
    });
    
    if (csvStatus && csvStatus.groups) {
      console.log("Received csvStatus complete and group list from server? " + csvStatus.complete)
      // console.log("csvStatus: " + JSON.stringify(csvStatus, null, 2))
      const csvDirpath = CSV_FILES + 'csv/'

      // // delete CSV dir, which had previously extracted files
      // fs.rmSync(csvDirpath, { recursive: true , force: true}, (err) => {
      //   if (err) {
      //       throw err;
      //   }
      // })
      // now clean the whole dir
      // https://stackoverflow.com/a/49421028
      try {
        const files = await readdir(CSV_FILES);
        for (let index = 0; index < files.length; index++) {
          const filename = files[index];
          console.log("Deleting old data: " + filename)
            fse.remove(CSV_FILES + filename, (err) => {
              if (err) {
                throw err;
              }
            })
        }
        console.log(`Deleted all files in ${CSV_FILES}`)
      } catch(err) {
        console.log('Error cleaning ' + CSV_FILES);
        console.log(err);
      }

      // save the csvStatus
      const writer = fs.writeFileSync(CSV_FILES + 'csvStatus.json', JSON.stringify(csvStatus));

      const outputPath = csvStatus.outputPath
      const outputFilename = outputPath.split('/')[2]
      const outputLocationUrl = env['tangerineURL'] + outputPath
      const outputLocationPath = CSV_FILES + outputFilename
      console.log("outputLocationPath: " + outputLocationPath + " outputLocationUrl: " + outputLocationUrl)

      console.log("Now downloading.")
      await downloadFile(outputLocationUrl, username, password, outputLocationPath) 
      console.log("Now extracting.")

      const zip = fs.createReadStream(outputLocationPath).pipe(unzipper.Parse({forceStream: true}));
      for await (const entry of zip) {
        const fileName = entry.path;
        const type = entry.type; // 'Directory' or 'File'
        const size = entry.vars.uncompressedSize; // There is also compressedSize;
        console.log("fileName: " + fileName + " size: " + size)
        // console.log("fileName: " + fileName)
        let groupId = fileName.replace('csv/','').replace('csv-data-sets-','').replace(dataSetIdentifier,'').replace('-group','group').replace('.zip','')
        const csvGroupdirpath = CSV_FILES + groupId + '/'
        // console.log("Creating group path: " + csvGroupdirpath)
        fs.mkdirSync(csvGroupdirpath)
        const simpleCSVZipfilename = 'csv-data-set.zip'
        // console.log("Writing zip file: " + csvGroupdirpath + fileName)
        entry.pipe(fs.createWriteStream(csvGroupdirpath + simpleCSVZipfilename))
      }

    } else {
      console.log("Error: no csvStatus. " )
    }

  } catch (error) {
    console.error(error)
    process.exit(1)
  }
}
go(params)