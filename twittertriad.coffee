root = exports ? this

root.Cards = new Meteor.Collection "cards"
root.Games = new Meteor.Collection "games"

SIZE = 3

if Meteor.isClient
  Meteor.startup ->
    Session.set "page", "game"
    Meteor.subscribe "cards"
    Meteor.subscribe "games"

  Handlebars.registerHelper 'equals', (name, value) ->
    Session.equals name, value

  Template.header.events
    "click #game": (e) ->
      Session.set "page", "game"

    "click #deck": (e) ->
      Session.set "page", "deck"

  Template.deck.events
    "click #load-cards": (e) ->
      Meteor.call "fetch"

  Template.deck.mycard = ->
    Cards.findOne twitterId: Meteor.user().services.twitter.id

  Template.deck.cards = ->
    user = Meteor.user()
    Cards.find 
      twitterId: $ne: user.services.twitter.id
      owner: user._id

  Template.game.events
    "click #new-game": (e) ->
      Meteor.call "newGame", (error, res) ->
        Session.set "game", res

  Template.game.game = ->
    id = Session.get "game"
    if id? then Games.findOne id

  Template.cardInner.tenEqualsA = (num) ->
    if num is 10 then 'A' else num

  Template.card.image = ->
    @image.replace "_normal", ""

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

  Template.playground.preserve
    ".card": (node) -> return node.id

  Template.deck.preserve
    ".card": (node) -> return node.id

  Template.hand.cards = -> 
    Cards.find _id: $in: this

  Template.playground.row = -> 
    res = []
    i = 1
    while i<=SIZE
      res.push
        row: i
      i++

    return res

  Template.playground.card =  (row, col) -> 
    card = Cards.findOne @field[row][col]
    if card?
      card.row = row
      card.col = col
      card.game = this
    return card

  Template.playground.field = (row, col) ->
    Cards.findOne @field[row][col]

  Template.playground.color = (row, col) ->
    if @color[row][col] is Meteor.userId() then "blue" else "red"

  Template.playground.events
    'click td': (e) ->
      gameId = Session.get "game"
      cardId = Session.get "selection"
      nr = $(e.currentTarget).data('field') - 1
      row = Math.floor nr/SIZE
      col = nr%SIZE
      Meteor.call "nextMove", gameId, cardId, row, col

if Meteor.isServer
  twitter = new Twitter()

  Meteor.startup ->
    Meteor.publish "cards", ->
      Cards.find owner: @userId

    Meteor.publish "games", ->
      Games.find players: @userId

Meteor.methods
  "nextMove": (gameId, cardId, row, col) ->
    if not gameId? and not _.isString gameId then throw new Meteor.Error 500, "no game"
    if not cardId? and not _.isString cardId then throw new Meteor.Error 500, "no card"
    if not row? and not _.isNumber row then throw new Meteor.Error 500, "no row"
    if not col? and not _.isNumber col then throw new Meteor.Error 500, "no col"

    # get game
    game = Games.findOne gameId
    if not game? then throw new Meteor.Error 500, "no game"

    if game.gameover then throw new Meteor.Error 500, "game over"
    if game.whosTurn isnt Meteor.userId() and game.whosTurn isnt "com" then throw new Meteor.Error 500, "Not your turn"
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

    # helper function to get the opposite direction
    opposite = (dir) ->
      switch dir
        when "top" then "bottom"
        when "bottom" then "top"
        when "left" then "right"
        when "right" then "left"

    # rule by which to flip cards
    rule = (card, row, col, dir, level) =>
      unless row >= 0 and row < SIZE and col >= 0 and row < SIZE and level <= 2
        return

      otherId = game.field[row][col]
      otherColor = game.color[row][col]

      if otherId? and otherColor isnt game.whosTurn
        otherCard = Cards.findOne otherId
        if card.ranks[dir] >= otherCard.ranks[opposite(dir)] 

          console.log "#{game._id}: #{card.name} flipped #{otherCard.name} (#{card.ranks[dir]} >= #{otherCard.ranks[opposite(dir)]})"
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
      game.gameover = true

      # determine winner
      points = _.countBy colors, (color) => if color is game.player1.id then game.player1.id else game.player2.id
      if points[game.player1.id] > points[game.player2.id]
        game.winner = game.player1.id 
      else 
        game.winner = game.player2.id

      console.log "#{game._id}: The winner is #{game.winner}!"

    # update game
    Games.update game._id, game

  "update": ->
    if Meteor.isServer
      num = Cards.find().count()

      func = (stat, rank) ->
        sort = {}
        sort["stats.#{stat}"] = 1

        cards = Cards.find {}, sort: sort

        i = 0
        cards.forEach (card) ->
          set = {}
          set.rank = card.rank + Math.round(i/num*10)
          set["ranks.#{rank}"] = Math.round(i/num*10)

          Cards.update card._id, $set: set

          i++

      func "followers", "top"
      func "friends", "left"
      func "statuses", "right"
      func "listed", "bottom"

  "fetch": ->
    if Meteor.isServer
      NUM_CARDS = 40
      Cards.remove {}
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
              rank: 0
              ranks:
                top: 0
                left: 0
                right: 0
                bottom: 0
              stats:
                followers: user.followers_count
                friends: user.friends_count
                statuses: user.statuses_count
                listed: user.listed_count

      Meteor.call "update"

  "newGame": ->
    if Meteor.isServer

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

      players = [Meteor.userId(), "com"]
      id = Games.insert
        players: players
        player1:
          id: players[0]
          hand: randomHand(6)
        player2:
          id: players[1]
          hand: randomHand(6)
        whosTurn: Random.choice players
        field: [[null, null, null, null], [null, null, null, null], [null, null, null, null]]
        color: [[null, null, null, null], [null, null, null, null], [null, null, null, null]]
        gameover: false
        winner: null

      return id
