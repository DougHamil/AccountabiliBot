Reddit = require './reddit'
NLP = require './nlp'
SunlightClient = require './sunlight'
BotDatabase = require './bot_database'
Bot = require './bot'
async = require 'async'
moment = require 'moment'
fs = require 'fs'

SUBREDDITS = ['stand', 'Technology', 'accountabili_bot', 'CISPA', 'FuturistParty', 'progressive', 'moderatepolitics', 'Corruption', 'lobbyists', 'government', 'Boise','maydaypac']
TEST_RUN = false
TOP_ORGS_ONLY = true
TOP_COUNT = 10

nlp = new NLP()
sunlight = new SunlightClient(process.argv[2])
reddit = new Reddit()
botDatabase = new BotDatabase()

bot = new Bot TOP_ORGS_ONLY, TOP_COUNT, TEST_RUN, SUBREDDITS, reddit, sunlight, nlp, botDatabase

onInitialized = ->
#processPost {url:TEST_URL, title:"TEST"}
  reddit.r(SUBREDDIT).new().call (err, listing) ->
    if err?
      console.error err
    else
      posts = listing.posts.filter (p) -> not p.is_self
      async.eachSeries posts, processPost, (err) ->
        if err?
          console.log err
        else
          console.log "Done. Waiting #{TIMEOUT/1000} seconds before retrying..."
          setTimeout onInitialized, TIMEOUT

async.series [botDatabase.init.bind(botDatabase), botDatabase.clearAllPostsBefore.bind(botDatabase, moment().subtract('weeks', 2)), reddit.init.bind(reddit)], (err) ->
  if err?
    console.log err
  else
    # Launch the bot and handle any errors
    bot.run (err) ->
      if err?
        console.log err
      process.exit(1)
