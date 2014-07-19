#
# Provides functions for Reddit API requests
#
sqlite = require('sqlite3').verbose()
request = require('request')
REDDIT_URL = 'http://www.reddit.com'
DATABASE_FILE = 'accountabili_bot_sqlite'

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

class Reddit
  constructor:(username, pass) ->

  r: (subreddit) ->
    return new Call(@).subreddit(subreddit)

  contributionsToMarkdown: (dateStr, beginDate, endDate, c) ->
    str = """
      # Contribution Report for **#{c.legislator.first_name + ' ' + c.legislator.last_name}** (#{dateStr})
      ## Top 10 Contributions By Organization:
      :---|---:
    """
    idx = 1
    for org in c.topOrganizations(10, beginDate, endDate)
      str += "#{idx}. #{org.organization}|#{org.amount.formatMoney()}\n"
      idx++

    str += """
      ## Top 10 Contributions by Category:
      :---|---:
    """
    idx = 1
    for org in c.topCategories(10, beginDate, endDate)
      str += "#{idx}. #{org.category}|#{org.amount.formatMoney()}\n"
      idx++
    str += """
      Total Contributions (#{dateStr}): **#{c.total(beginDate, endDate).formatMoney()}**
      *****
      *Powered by [Sunlight Foundation](http://sunlightfoundation.com/), [OpenSecrets.org](https://www.opensecrets.org/), and [Alchemy API](http://www.alchemyapi.com/)*
    """
    return str


module.exports = Reddit
