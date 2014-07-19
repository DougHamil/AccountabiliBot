# Simple interface to Neo4J database

Neo4j = require 'neo4j'

class Database
  constructor:(@_host) ->
    @db = new Neo4j.GraphDatabase(@_host)

  addPolitician: (p, cb) ->
    @db.getIndexedNodes 'bioguide id',

module.exports = Database
