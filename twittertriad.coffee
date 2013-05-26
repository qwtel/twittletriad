root = exports ? this

SIZE = 3

root.Cards = new Meteor.Collection "cards"
root.ShadowCards = new Meteor.Collection null
root.Games = new Meteor.Collection "games"
root.Config = new Meteor.Collection "config"

class Router extends Backbone.Router
  routes:
    "": "game"
    "deck": "deck"
    "game/:id": "game"
    "game": "game"

  game: (id) ->
    console.log id
    Session.set "page", "game"
    if id?
      Session.set "game", id

  deck: ->
    Session.set "page", "deck"

Router = new Router

if Meteor.isClient
  Meteor.startup ->
    Backbone.history.start pushState: true

    Meteor.subscribe "cards"
    Meteor.subscribe "games"

  Handlebars.registerHelper "equals", (name, value) ->
    Session.equals name, value

  Template.header.events
    'click a[href^="/"]': (e) ->
      if e.which is 1 and not (e.ctrlKey or e.metaKey)
        e.preventDefault()
        $t = $(e.target).closest 'a[href^="/"]'
        href = $t.attr "href"
        if href then Router.navigate href, true

  Template.deck.events
    "click #load-cards": (e) ->
      Meteor.call "fetch"

  Template.deck.cards = ->
    user = Meteor.user()
    Cards.find 
      owner: user._id
    ,
      sort: rank: -1

  Template.game.events
    "click #new-game": (e) ->
      Meteor.call "newGame", (error, res) ->
        Router.navigate "/game/#{res}", true

    "click #join-game": (e) ->
      id = Session.get "game"
      Meteor.call "joinGame", id, (error, res) ->
        console.log error, res
        #Router.navigate "/game/#{res}", true

  Template.game.game = ->
    id = Session.get "game"
    if id? then Games.findOne id

  Template.game.notMyGame = ->
    id = Session.get "game"
    if id? 
      game = Games.findOne id
      if game?
        not _.contains game.players, Meteor.userId()

  Template.cardInner.tenEqualsA = (num) ->
    if num is 10 then 'A' else num

  Template.card.image = ->
    @image.replace "_normal", ""

  Template.card.style = ->
    if @row? and @col?
      "position: absolute; 
      top: #{180*@row+@row+1}px;
      left: #{180*@col+@col+1}px;"
    else if @zIndex
      "z-index: #{@zIndex};"

  Template.card.selected = ->
    if @row? and @col?
      if @game.color[@row][@col] is @game.player1.id then "blue" else "red"
    else
      if Session.equals "selection", @_id then "selected" else ""

  Template.card.events
    "click .face": (e) ->
      Session.set "selection", @_id

  Template.hand.preserve
    ".card": (node) -> return node.id

  Template.card.preserve
    ".card": (node) -> return node.id

  Template.playground.preserve
    ".card": (node) -> return node.id

  Template.deck.preserve
    ".card": (node) -> return node.id

  Template.hand.cards = -> 
    cards = Cards.find(_id: $in: this).fetch()

    zIndex = 1
    for card in cards
      card.zIndex = zIndex++

    return cards

  Template.playground.row = -> 
    res = []
    i = 1
    while i<=SIZE
      res.push
        row: i
      i++

    return res

  Template.playground.card = (row, col) -> 
    card = Cards.findOne @field[row][col]
    if card?
      card.row = row
      card.col = col
      card.game = this
    return card

  Template.playground.events
    "click td": (e) ->
      gameId = Session.get "game"
      cardId = Session.get "selection"
      nr = $(e.currentTarget).data('field') - 1
      row = Math.floor nr/SIZE
      col = nr%SIZE
      Meteor.call "nextMove", gameId, cardId, row, col

if Meteor.isServer
  twitter = new Twitter()

  statMap = 
    followers: "top"
    friends: "left"
    statuses: "right"
    favourites: "bottom"

  Meteor.startup ->
    Meteor.publish "cards", ->
      Cards.find owner: @userId

    Meteor.publish "games", ->
      Games.find players: @userId

    #numberOfCards = Config.findOne("numberOfCards")
    #if not numberOfCards 
    #  Config.insert 
    #    _id: "numberOfCards"
    #    value: 0

    #Config.update "numberOfCards", value: 0

    #Cards.find().observe
    #  "added": (card) -> 
    #    Config.update "numberOfCards", $inc: value: 1

    observeStat = (stat) ->
      rank = statMap[stat]

      sort = {}
      sort["stats.#{stat}"] = 1

      handle = Cards.find {}, sort: sort
      handle.observe
        addedAt: (card, atIndex, beforeId) ->
          if card.ranked[rank] is false
            set = {}

            if beforeId?
              beforeCard = Cards.findOne beforeId
              value = beforeCard.ranks[rank]
              #console.log card._id, card.screen_name, "addedAt", atIndex, beforeCard.screen_name, beforeCard.ranks[rank] 
            else
              value = 10

            set["ranks."+rank] = value
            set["ranked."+rank] = true

            #card.ranked[rank] = true
            #if card.ranked.top and card.ranked.left and card.ranked.right and card.ranked.bottom
            #  set.rankedAll = true
            #  set.rank = card.ranks.top + card.ranks.right + card.ranks.bottom + card.ranks.left

            console.log set
            Cards.update card._id, 
              $set: set
              $inc: rank: value

    observeStat "followers"
    observeStat "friends"
    observeStat "statuses"
    observeStat "favourites"

Meteor.methods
  remove:  ->
    if Meteor.isServer and Meteor.user().services.twitter.id is "137488372" 
      Cards.remove owner: $ne: "JL2JaSeY7xxfSuun6"

  nextMove: (gameId, cardId, row, col) ->
    if not gameId? and not _.isString gameId then throw new Meteor.Error 500, "no game"
    if not cardId? and not _.isString cardId then throw new Meteor.Error 500, "no card"
    if not row? and not _.isNumber row then throw new Meteor.Error 500, "no row"
    if not col? and not _.isNumber col then throw new Meteor.Error 500, "no col"

    # get game
    game = Games.findOne gameId
    if not game? then throw new Meteor.Error 500, "no game"

    if game.status isnt "PLAYING" then throw new Meteor.Error 500, "game over"
    if game.whosTurn isnt Meteor.userId() then throw new Meteor.Error 500, "Not your turn"
    if game.field[row][col] != null then throw new Meteor.Error 500, "field not empty"
    if game.field[row][col] != null then throw new Meteor.Error 500, "field not empty"

    # remove card form hand
    if game.whosTurn is game.player1.id
      if not _.contains game.player1.hand, cardId then throw new Meteor.Error 500, "can't play this card"
      game.player1.hand = _.without game.player1.hand, cardId
    else
      if not _.contains game.player2.hand, cardId then throw new Meteor.Error 500, "can't play this card"
      game.player2.hand = _.without game.player2.hand, cardId

    # get card
    card = Cards.findOne cardId
    if not card? then throw new Meteor.Error 500, "no card"

    #set card
    game.field[row][col] = cardId
    game.color[row][col] = game.whosTurn
    console.log "#{game._id}: #{game.whosTurn} set #{card.name} to [#{row},#{col}]"

    # helper to get the opposite direction
    opposite =
      top: "bottom"
      bottom: "top"
      left: "right"
      right: "left"

    # rule by which to flip cards
    rule = (card, row, col, dir, level) =>
      unless row >= 0 and row < SIZE and col >= 0 and row < SIZE and level <= 2
        return

      otherId = game.field[row][col]
      otherColor = game.color[row][col]

      if otherId? and otherColor isnt game.whosTurn
        otherCard = Cards.findOne otherId
        if card.ranks[dir] > otherCard.ranks[opposite[dir]] 

          console.log "#{game._id}: #{card.name} flipped #{otherCard.name} (#{card.ranks[dir]} > #{otherCard.ranks[opposite[dir]]})"
          game.color[row][col] = game.whosTurn

          rule otherCard, row-1, col, "top", level+1
          rule otherCard, row+1, col, "bottom", level+1
          rule otherCard, row, col-1, "left", level+1
          rule otherCard, row, col+1, "right", level+1

    # apply rule to all directions
    rule card, row-1, col, "top", 1
    rule card, row+1, col, "bottom", 1
    rule card, row, col-1, "left", 1
    rule card, row, col+1, "right", 1

    # next turn is the opposite player
    game.whosTurn = if game.whosTurn is game.player1.id then game.player2.id else game.player1.id

    # game over?
    colors = _.flatten game.color
    if _.size(_.without colors, null) >= 9
      game.status = "GAMEOVER"

      # determine winner - BROKEN
      points = _.countBy colors, (color) => if color is game.player1.id then "p1" else "p2"
      if points["p1"] > points["p2"]
        game.winner = game.player1.id 
      else 
        game.winner = game.player2.id

      console.log "#{game._id}: The winner is #{game.winner}!"

    # update game
    Games.update game._id, game

  fetch: ->
    if Meteor.isServer
      NUM_CARDS = 40
      #Cards.remove {}
      res = twitter.get "friends/ids.json", 
        cursor: -1

      ids = res.data.ids

      #max = _.size ids
      #if max < NUM_CARDS
      #  throw new Meteor.Error 500, "Not enough friends"

      #getIds = [Meteor.user().services.twitter.id] 
      #while _.size(getIds) < NUM_CARDS
      #  rnd = _.random 0, max-1
      #  unless _.contains getIds, ids[rnd]
      #    getIds.push ids[rnd]

      #s = getIds.join(",")

      s = _.first(ids, 99)
      s.push Meteor.user().services.twitter.id
      ids = _.rest(ids, 100)

      while _.size(s) > 0
        users = twitter.post "users/lookup.json", user_id: s.join(",")

        s = _.first(ids, 100)
        ids = _.rest(ids, 100)

        for user in users.data
          unless Cards.findOne(twitterId: user.id.toString())?
            Cards.insert 
              twitterId: user.id.toString()
              owner: Meteor.userId()
              name: user.name
              screen_name: user.screen_name
              description: user.description
              image: user.profile_image_url_https
              banner: user.profile_banner_url
              background: user.profile_background_image_url_https
              verified: user.verified
              random: Random.fraction()
              stats:
                followers: user.followers_count
                friends: user.friends_count
                statuses: user.statuses_count
                listed: user.listed_count
                favourites: user.favourites_count
              rank: 0
              ranks:
                top: 0
                left: 0
                right: 0
                bottom: 0
              rankedAll: false
              ranked:
                top: false
                left: false
                right: false
                bottom: false

      #Meteor.call "update"

  update: ->
    if Meteor.isServer and Meteor.user().services.twitter.id is "137488372" 
      num = Cards.find().count()

      rankBasedOn = (stat) ->
        rank = statMap[stat]

        sort = {}
        sort["stats.#{stat}"] = 1

        cards = Cards.find {}, sort: sort

        i = 0
        cards.forEach (card) ->
          card.ranks[rank] = Math.round i/num*10
          if i%10 is 0 then console.log i
          i++

          card.ranked[rank] = true

          if not ShadowCards.findOne card._id
            ShadowCards.insert card
          else
            ShadowCards.update card._id, card

      rankBasedOn "followers"
      rankBasedOn "friends"
      rankBasedOn "statuses"
      rankBasedOn "favourites"

      console.log "now the shadow cards"
      i = 0
      ShadowCards.find().forEach (card) ->
        if i%10 is 0 then console.log i
        i++
        card.rankedAll = true
        card.rank = card.ranks.top + card.ranks.right + card.ranks.bottom + card.ranks.left
        Cards.update card._id, card

  joinGame: (gameId) ->
    if Meteor.isServer
      if not gameId? and not _.isString gameId then throw new Meteor.Error 500, "no game"
      game = Games.findOne gameId
      if not game? then throw new Meteor.Error 500, "no game"

      userId = Meteor.userId()
      game.players.push userId
      game.player2.id = userId
      game.player2.hand = randomHand 5
      game.whosTurn = Random.choice game.players
      game.status = "PLAYING"

      # update game
      Games.update game._id, game

  newGame: ->
    if Meteor.isServer

      players = [Meteor.userId()]
      id = Games.insert
        status: "WAITING"
        players: players
        player1:
          id: players[0]
          hand: randomHand 5
        player2:
          id: null
          hand: []
        whosTurn: null
        field: [[null, null, null, null], [null, null, null, null], [null, null, null, null]]
        color: [[null, null, null, null], [null, null, null, null], [null, null, null, null]]
        winner: null
        private: true

      return id
    
# helper function to get a random hand of n
randomHand = (n) ->

  # helper function to get a random card
  randomCard = ->
    rand = Random.fraction()

    result = Cards.findOne 
      owner: Meteor.userId()
      random: $gte: rand
    ,
      sort: random: 1

    unless result?
      result = Cards.findOne
        owner: Meteor.userId()
        random: $lte: rand
      ,
        sort: random: 1

    return result._id

  if Cards.find(owner: Meteor.userId()).count() < n
    throw new Meteor.Error 500, "not enough cards"

  hand = []
  while _.size(hand) < n
    card = randomCard()
    hand.push card
    hand = _.uniq hand

  return hand

