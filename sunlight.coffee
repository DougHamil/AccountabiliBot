# Client for Sunlight Foundation API

request = require 'request'
#csv = require 'csv'
fs = require 'fs'
moment = require 'moment'
natural = require 'natural'

ROOT_URL = 'http://congress.api.sunlightfoundation.com/'
TRAN_URL = 'http://transparencydata.com/api/1.0/'

FUZZY_MATCH_THRESHOLD = 0.7

Number::formatMoney = (t=',', d='.', c='$') ->
  n = this
  if n == 0
    return "$0"
  s = if n < 0 then "-#{c}" else c
  i = Math.abs(n).toFixed(2)
  j = (if (j = i.length) > 3 then j % 3 else 0)
  s += i.substr(0, j) + t if j
  return s + i.substr(j).replace(/(\d{3})(?=\d)/g, "$1" + t)

CONTRIBUTOR_CATEGORIES = {}
###
catcodes = fs.readFileSync('catcodes.csv', 'utf8')
lines = catcodes.split('\n')
for line in lines
  row = []
  cols = line.split(',')
  for col in cols
    col = col.replace /"/g, ''
    row.push col
  CONTRIBUTOR_CATEGORIES[row[1]] = row[3] + ": " + row[2]
###

class Contributions
  constructor: (@legislator, @_data) ->
    # Denormalize
    @categories = @_indexAmountByProperty 'contributor_category', (c) -> CONTRIBUTOR_CATEGORIES[c]
    @organizations = @_indexAmountByProperty('organization_name')
    #@totalContributions = (@_data.map (c) -> parseFloat(c.amount)).reduce (t, s) -> t + s

  topCategories: (n, bdate, edate) ->
    cats = {}
    if bdate?
      cats = @_indexAmountByProperty('contributor_category', ((c) -> CONTRIBUTOR_CATEGORIES[c]), (c) -> moment(c.date).isAfter(bdate) and moment(c.date).isBefore(edate))
    else
      cats = @categories
    top = ({category:cat, amount:amt} for cat, amt of cats)
    top.sort (a,b) ->
      return b.amount - a.amount
    return top.splice(0, n)

  topOrganizations: (n, bdate, edate) ->
    orgs = {}
    if bdate?
      orgs = @_indexAmountByProperty('organization_name', null, (c) -> moment(c.date).isAfter(bdate) and moment(c.date).isBefore(edate))
    else
      orgs = @_indexAmountByProperty('organization_name')
    top = ({organization:org, amount:amt} for org, amt of orgs)
    top.sort (a,b) ->
      return b.amount - a.amount
    return top.splice(0, n)

  total: (bdate, edate) ->
    total = 0
    for c in @_data
      if moment(c.date).isAfter(bdate) and moment(c.date).isBefore(edate)
        total += parseFloat(c.amount)
    return total

  _indexAmountByProperty: (prop, t, f) ->
    map = {}
    for c in @_data
      if f? and not f(c)
        continue
      val = c[prop]
      if val == ''
        continue
      try
        amt = parseFloat(c.amount)
        if val?
          if t?
            val = t(val)
          if not map[val]?
            map[val] = 0
          map[val] += amt
      catch err
    return map

class Client
  constructor:(@_key) ->

  findBestMatch: (first, last, results) ->
    if results.length == 0
      return null

    withScores = []
    # Search by First Name
    for r in results
      dist = natural.JaroWinklerDistance first, r.first_name
      withScores.push {result:r,score:dist}
    withScores.sort (a, b) -> a.score - b.score
    best = withScores[0]
    if best.score >= FUZZY_MATCH_THRESHOLD
      return best.result
    else
      console.log "Not best match:"
      console.log best
      withScores = []
      # Search by nick name
      for r in results
        if r.nickname?
          dist = natural.JaroWinklerDistance first, r.nickname
          withScores.push {result:r, score:dist}
      if withScores.length > 0
        withScores.sort (a, b) -> a.score - b.score
        best = withScores[0]
        if best.score >= FUZZY_MATCH_THRESHOLD
          return best.result
    return null

  searchForLegislatorByName: (first, last, cb) ->
    # Search only by last name
    url = ROOT_URL + "legislators?apikey=#{@_key}&last_name=#{encodeURIComponent(last)}"
    request {url:url, json:true}, (err, resp, body) =>
      if err?
        cb err
      else
        if body.results? and body.results.length > 0
          cb err, @findBestMatch(first, last, body.results)
        else
          cb null, null

  getEntityIdForLegislator: (leg, cb) ->
    url = TRAN_URL + "entities/id_lookup.json?namespace=urn%3Acrp%3Arecipient&id=#{leg.crp_id}&apikey=#{@_key}"
    request {url:url, json:true}, (err, resp, body) =>
      if not err? and body.length > 0
        cb err, body[0].id
      else
        cb err, null

  getTopContributionsForLegislator:(leg, count, cb) ->
    @getEntityIdForLegislator leg, (err, entityId) =>
      if err? or not entityId?
        cb err, null
      else
        url = TRAN_URL + "aggregates/pol/#{entityId}/contributors.json?limit=#{count}&apikey=#{@_key}"
        request {url:url, json:true}, (err, resp, body) =>
          if not err?
            cb err, {legislator:leg, data:body}
          else
            cb err, body

  getContributionsForLegislator:(leg, cb) ->
    url = TRAN_URL + "contributions.json?apikey=#{@_key}&recipient_ft=#{encodeURIComponent(leg.first_name+' '+leg.last_name)}"
    request {url:url, json:true}, (err, resp, body) =>
      if not err?
        if body.length > 0
          cb err, new Contributions(leg, body)
        else
          # Search by Nick name
          url = TRAN_URL + "contributions.json?apikey=#{@_key}&recipient_ft=#{encodeURIComponent(leg.nickname+' '+leg.last_name)}"
          request {url:url, json:true}, (err, resp, body) =>
            if err?
              cb err, body
            else if body.length > 0
              cb err, new Contributions(leg, body)
            else
              cb err, null
      else
        cb err, body

  searchForBillsByLegislator: (leg, cb) ->
    url = ROOT_URL + "bills?apikey=#{@_key}&sponsor_id=#{leg.bioguide_id}"
    bills = []
    request {url:url, json:true}, (err, resp, body) =>
      if not err?
        bills = body.results
        # Get co-sponsored
        url = ROOT_URL + "bills?apikey=#{@_key}&cosponsor_id=#{leg.bioguide_id}"
        request {url:url, json:true}, (err, resp, body) =>
          if not err?
            cb err, bills.concat body.results
          else
            cb new Error("Error getting Bills")
      else
        cb new Error("Error getting Bills")

module.exports = Client
