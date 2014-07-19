# Get Top Reddit Tech posts
Reddit = require './reddit'
NLP = require './nlp'
SunlightClient = require './sunlight'
BotDatabase = require './bot_database'
async = require 'async'
moment = require 'moment'
fs = require 'fs'

nlp = new NLP()
sunlight = new SunlightClient(process.argv[2])
reddit = new Reddit()
botDatabase = new BotDatabase()

TEST_URL = "http://motherboard.vice.com/read/meet-marsha-blackburn-big-telecoms-best-friend-in-congress"

postComment = (post, comment, cb) ->
  reddit.comment post.name, comment, cb

processPost = (post, cb) ->
  url = post.url
  botDatabase.hasPosted post, (err, hasPosted) ->
    if err?
      cb err
    else
      if hasPosted
        console.log "SKIPPING: #{post.title}"
        cb null
      else
        # Double check by hitting reddit
        reddit.hasComment post.subreddit, post.id, (err, hasComment) ->
          if err?
            cb err
          else
            botDatabase.markPosted post, (err) ->
              if err?
                cb err
              else
                if hasComment
                  console.log "SKIPPING: #{post.title}"
                  cb null
                else
                  console.log "PROCESSING: #{post.title}"
                  readPost post.url, (err, comment) ->
                    if err?
                      cb err
                    else
                      if comment?
                        console.log "POSTING COMMENT: #{post.title}"
                        postComment post, comment, cb
                      else
                        cb err, comment

readPost = (url, cb) ->
  comment = null
  nlp.entities url, (err, entities) ->
    if err?
      cb err
    procEntity = ->
      if entities.length == 0
        if comment?
          comment += "\n"+reddit.creditsMarkdown()
        cb null, comment
        return
      entity = entities.pop()
      if entity.type is 'Person'
        name = if entity.disambiguated? then entity.disambiguated.name else entity.text
        names = name.split(' ')
        names = names.filter (n) -> n.indexOf('.') == -1
        if names.length > 2
          names.splice(1,1)
        first_name = names[0]
        last_name = names[names.length - 1]
        sunlight.searchForLegislatorByName first_name, last_name, (err, l) ->
          if l?
            sunlight.getContributionsForLegislator l, (err, contribs) ->
              if err?
                procEntity()
              else
                start = moment().subtract('years',1).startOf('year').subtract('days', 1)
                end = moment()
                str = moment().subtract('years', 1).format('YYYY') + ' to Date'
                # Only generate markdown if there were contributions
                if contribs.total(start, end) > 0
                  if not comment?
                    comment = ""
                  else
                    comment += "\n*****\n"
                  markDown = reddit.contributionsToMarkdown(str, start, end, contribs)
                  comment += markDown
                else
                  console.log "Total contributions is $0:"
                  console.log contribs
                procEntity()
          else
            procEntity()
      else
        procEntity()
    procEntity()

onInitialized = ->
#processPost {url:TEST_URL, title:"TEST"}
  reddit.r('accountabili_bot').new().call (err, listing) ->
    if err?
      console.error err
    else
      posts = listing.posts.filter (p) -> not p.is_self
      async.eachSeries posts, processPost, (err) ->
        if err?
          console.log err
        else
          console.log "Done. Waiting 10 seconds before retrying..."
          setTimeout onInitialized, 10000

async.series [botDatabase.init.bind(botDatabase), botDatabase.clearAllPostsBefore.bind(botDatabase, moment().subtract('weeks', 2)), reddit.init.bind(reddit)], (err) ->
  if err?
    console.log err
  else
    onInitialized()
