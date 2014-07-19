AlchemyAPI = require('./alchemyapi')
alApi = new AlchemyAPI()

class Entity
  constructor:(@_data) ->
    for key, val of @_data
      @[key] = val

class NLP
  constructor: ->
  entities: (url, cb) ->
    alApi.entities 'url', url, {}, (resp) ->
      cb null, (resp.entities.map (e) -> new Entity(e))

module.exports = NLP
