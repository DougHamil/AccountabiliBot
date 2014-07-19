# Client for Sunlight Foundation API

request = require 'request'
csv = require 'csv'
fs = require 'fs'
moment = require 'moment'

ROOT_URL = 'http://congress.api.sunlightfoundation.com/'
TRAN_URL = 'http://transparencydata.com/api/1.0/'

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
catcodes = fs.readFileSync('catcodes.csv', 'utf8')
lines = catcodes.split('\n')
for line in lines
  row = []
  cols = line.split(',')
  for col in cols
    col = col.replace /"/g, ''
    row.push col
  CONTRIBUTOR_CATEGORIES[row[1]] = row[2] + " -> " + row[3]

class Contributions
  constructor: (@legislator, @_data) ->
    # Denormalize
    @categories = @_indexAmountByProperty 'contributor_category', (c) -> CONTRIBUTOR_CATEGORIES[c]
    @organizations = @_indexAmountByProperty('organization_name')
    @totalContributions = (@_data.map (c) -> parseFloat(c.amount)).reduce (t, s) -> t + s

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

  _parseCategoryCodes: ->

class Client
  constructor:(@_key) ->

  searchForLegislatorByName: (first, last, cb) ->
    url = ROOT_URL + "legislators?apikey=#{@_key}&first_name=#{encodeURIComponent(first)}&last_name=#{encodeURIComponent(last)}"
    request {url:url, json:true}, (err, resp, body) ->
      if body.results? and body.results.length > 0
        cb err, body.results[0]
      else
        cb new Error("Legislator not found for #{first} #{last}")

  getContributionsForLegislator:(leg, cb) ->
    url = TRAN_URL + "contributions.json?apikey=#{@_key}&recipient_ft=#{encodeURIComponent(leg.first_name+' '+leg.last_name)}"
    request {url:url, json:true}, (err, resp, body) =>
      if not err?
        cb err, new Contributions(leg, body)
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
