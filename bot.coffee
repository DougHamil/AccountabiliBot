fs = require 'fs'
async = require 'async'
moment = require 'moment'

TIMEOUT = 60000

# Tags corresponding to disambiguation from Alchemy API
POL_TAGS = ['Politician', 'OfficeHolder', 'U.S.Congressperson']

class Bot
  constructor:(@topOrgsOnly, @topOrgsCount, @testRun, @subreddits, @reddit, @sunlight, @nlp, @database) ->

  _tagsContains: (tags) ->
    if not tags?
      return false
    for t in POL_TAGS
      if t in tags
        return true
    return false

  _buildCommentForEntity: (entity, cb) ->
    dis = entity.disambiguated
    if entity.type is 'Person' and dis? and @_tagsContains(dis.subType)
      name = if entity.disambiguated? then entity.disambiguated.name else entity.text
      names = name.split(' ')
      names = names.filter (n) -> n.indexOf('.') == -1
      if names.length > 2
        names.splice(1,1)
      first_name = names[0]
      last_name = names[names.length - 1]
      console.log "Searching for #{first_name} #{last_name} (#{name})"
      @sunlight.searchForLegislatorByName first_name, last_name, (err, l) =>
        if err? or not l?
          cb err
        else
          if @topOrgsOnly
            @sunlight.getTopContributionsForLegislator l, @topOrgsCount, (err, contribs) =>
              if err? or not contribs?
                cb err
              else
                str = "Career"
                # Only generate comment if there is data
                if contribs.data.length > 0
                  cb null, @reddit.topContributionsToMarkdown(str, contribs)
                else
                  cb null, null
          else
            @sunlight.getContributionsForLegislator l, (err, contribs) =>
              if err? or not contribs?
                cb err
              else
                start = moment().subtract('years',1).startOf('year').subtract('days', 1)
                end = moment()
                str = moment().subtract('years', 1).format('YYYY') + ' to Date'
                # Only generate markdown if there were contributions
                if contribs.total(start, end) > 0
                  cb null, @reddit.contributionsToMarkdown(str, start, end, contribs)
                else
                  cb null, null
    else
      cb null, null

  _createCommentForPost: (url, cb) ->
    @nlp.entities url, (err, entities) =>
      if err?
        cb err
      else
        async.mapSeries entities, @_buildCommentForEntity.bind(@), (err, comments) =>
          if err?
            cb err
          else
            combinedComment = null
            for comment in comments
              if comment?
                if combinedComment?
                  old = combinedComment
                  combinedComment += "\n*****\n"
                  combinedComment += comment
                  # Ignore if too big
                  if combinedComment.length >= 10000
                    combinedComment = old
                else
                  combinedComment = comment
            if combinedComment?
              combinedComment += "\n"
              combinedComment += @reddit.creditsMarkdown()
            cb err, combinedComment

  _processPost: (post, cb) ->
    @database.hasPosted post, (err, hasPosted) =>
      if err?
        cb err
      else
        if hasPosted
          console.log "SKIPPING: #{post.title}"
          cb null
        else
          # Double check we haven't commented already
          @reddit.hasComment post.subreddit, post.id, (err, hasComment) =>
            if err?
              cb err
            else
              if hasComment
                console.log "SKIPPING: #{post.title}"
                cb null
              else
                console.log "READING: #{post.title}"
                @_createCommentForPost post.url, (err, comment) =>
                  if err?
                    cb err
                  else
                    @database.markPosted post, (err) =>
                      if err?
                        cb err
                      else
                        if comment?
                          if @testRun
                            console.log "WRITING COMMENT TO FILE: #{post.name}"
                            fs.writeFileSync post.name + ".md", comment
                            cb null, comment
                          else
                            console.log "POSTING COMMENT: #{post.title}"
                            @reddit.comment post.name, comment, (err) =>
                              if err?
                                console.log "COMMENT POST ERROR:"
                                console.log err
                              # Ignore posting errors
                              cb null
                        else
                          cb err, comment

  _handleSubreddit: (sub, cb) ->
    @reddit.r(sub).hot().call (err, listing) =>
      if err?
        cb err
      else
        # No self-posts
        posts = listing.posts.filter (p) -> not p.is_self
        async.eachSeries posts, @_processPost.bind(@), cb

  _run: (cb) ->
    async.eachSeries @subreddits, @_handleSubreddit.bind(@), (err) =>
      if err?
        cb err
      else
        setTimeout @_run.bind(@, cb), TIMEOUT

  run: (cb)->
    setTimeout @_run.bind(@, cb), 0

module.exports = Bot
