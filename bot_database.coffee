# SQLite DB for tracking bot activity
sqlite = require('sqlite3').verbose()
async = require 'async'
moment = require 'moment'
FILE_NAME = './bot.db'
POST_TABLE_NAME = 'Posts'

class Database
  constructor: (cb)->

  init: (cb) ->
    # Run each initialization routine
    @_db = new sqlite.Database FILE_NAME, sqlite.OPEN_READWRITE | sqlite.OPEN_CREATE, (err) =>
      if err?
        cb err
      else
        async.series [@_initPostTable.bind(@)], (err) ->
          cb err

  clearAllPostsBefore: (time, cb) ->
    @_db.serialize =>
      @_db.run "DELETE FROM #{POST_TABLE_NAME} WHERE timestamp < ?;", [moment(time).format()], cb

  hasPosted: (post, cb) ->
    @_db.serialize =>
      @_db.get "SELECT * FROM #{POST_TABLE_NAME} WHERE post_id = ? AND has_posted = 1", [@idForPost(post)], (err, val) =>
        if err?
          cb err
        else
          if not val?
            cb null, false
          else
            cb null, true

  markPosted: (post, cb) ->
    postId = @idForPost(post)
    @_db.serialize =>
      @_db.run "INSERT OR REPLACE INTO #{POST_TABLE_NAME} (post_id, has_posted) VALUES (?, 1)", [postId], cb

  markUnposted: (post, cb) ->
    postId = @idForPost(post)
    @_db.serialize =>
      @_db.run "INSERT OR REPLACE INTO #{POST_TABLE_NAME} (post_id, has_posted) VALUES (?, 0)", [postId], cb

  idForPost:(post) ->
    return post.name

  _initPostTable: (cb) ->
    @_db.serialize =>
      @_db.get "SELECT * FROM #{POST_TABLE_NAME}", (err) =>
        # Error on table not found
        if err?
          @_db.run "CREATE TABLE #{POST_TABLE_NAME} (post_id TEXT PRIMARY KEY NOT NULL, has_posted BOOLEAN NOT NULL DEFAULT 0, timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP)", (err) =>
            if not err?
              console.log "Created posts table."
            cb err
        else
          cb null


module.exports = Database
