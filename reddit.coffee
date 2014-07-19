#
# Provides functions for Reddit API requests
#
rawjs = require 'raw.js'
raw = new rawjs('Accountabili-Bot')
sqlite = require('sqlite3').verbose()
request = require('request')
REDDIT_URL = 'http://www.reddit.com'
DATABASE_FILE = 'accountabili_bot_sqlite'

raw.setupOAuth2(process.argv[3], process.argv[4])

class Post
  constructor:(@_call, @_listing, @data) ->
    @data = @data.data
    for key, val of @data
      @[key] = val

class Listing
  constructor:(@_call, @data) ->
    @data = @data.data
    @posts = []
    for child in @data.children
      @posts.push new Post(@_call, @, child)
    @before = @data.before
    @after = @data.after

  more: (cb) ->
    @_call.before(null).after(null).after(@posts[-1].id).call(cb)

class Call
  constructor:(@reddit) ->
  call: (cb) ->
    url = REDDIT_URL+"/r/#{@_subreddit}/#{@_filter}.json?"
    if @_after?
      url += "after=#{@_after}&"
    if @_before?
      url += "before=#{@_before}&"
    if @_limit?
      url += "limit=#{@_limit}&"
    request {url:url, json:true}, (err, response, body) =>
      if err
        cb err
      else
        cb err, new Listing(@, body)
  subreddit:(@_subreddit) -> return @
  filter: (@_filter) -> return @
  after: (@_after) -> return @
  before: (@_before) -> return @
  limit: (@_limit) -> return @
  new:-> @filter('new')
  top:-> @filter('top')
  hot:-> @filter('hot')

toTitleCase = (str) ->
    str.replace /\w\S*/g, (txt) -> # see comment below
        txt[0].toUpperCase() + txt[1..txt.length - 1].toLowerCase()

class Reddit
  constructor: ->

  init: (cb) ->
    raw.auth {"username":"Accountabili_bot", "password":process.argv[5]}, cb

  r: (subreddit) ->
    return new Call(@).subreddit(subreddit)

  hasComment: (subreddit, thing, cb) ->
    url = REDDIT_URL + "/r/#{subreddit}/comments/#{thing}.json?depth=1&limit=1000&sort=old"
    request {url:url, json:true}, (err, resp, body) ->
      if err?
        cb err
      else
        for comment in body
          if comment.kind == 'Listing'
            for child in comment.data.children
              if child.data?.author == "Accountabili_bot"
                cb null, true
                return
        cb null, false

  comment: (thing, text, cb) ->
    raw.comment thing, text, cb

  contributionsToMarkdown: (dateStr, beginDate, endDate, c) ->
    str = """
      # Contribution Report for **#{c.legislator.first_name + ' ' + c.legislator.last_name}** (#{dateStr})
      ## Top 10 Contributions By Organization:
      Organization|Amount
      :-------|-------:
    """
    idx = 1
    for org in c.topOrganizations(10, beginDate, endDate)
      str += "\n#{idx}. #{org.organization}|#{org.amount.formatMoney()}"
      idx++

    str += """\n
      ## Top 10 Contributions by Category:
      Category|Amount
      :-------|-------:
    """
    idx = 1
    for org in c.topCategories(10, beginDate, endDate)
      str += "\n#{idx}. #{toTitleCase(org.category)}|#{org.amount.formatMoney()}"
      idx++
    str += """\n
      Total Contributions (#{dateStr}): **#{c.total(beginDate, endDate).formatMoney()}**
    """
    return str
  creditsMarkdown: ->
    return """
      *****
      *Powered by [Sunlight Foundation](http://sunlightfoundation.com/), [OpenSecrets.org](https://www.opensecrets.org/), and [Alchemy API](http://www.alchemyapi.com/)*
    """


module.exports = Reddit
