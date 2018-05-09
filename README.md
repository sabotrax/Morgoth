# Morgoth
## A Discord bot for Star Citizen

### What it is

Morgoth is a Discord bot that can be a helper and
general source of fun.

Features:

* Remember and recall factoids.
* User management.
* Download database on the fly.
* Greeting new users with configurable in-bot messages.
* Rolling dice.

### Documentation

Overview:

The bot's primary job is to store and display factoids. A factoid is made up of a keyword and some text.

Everybody on the Discord server can execute non-writing bot commands, like asking the bot about stuff.

Only users known to the bot can execute writing commands, like adding new stuff or creating aliases.

Users known as bot masters can elevate others.

Commands:

NAME

~define - store factiods

SYNOPSIS

~define [ --alias alias keyword ] [ --hidden ] [ --primer keyword ( true | false ) ] ( keyword | other-keyword | "just another keyword" ) text

DESCRIPTION

Only one long option is allowed at a time.

--alias - Creates an alias to the keyword

--hidden - Creates a hidden keyword. Hidden keywords are not shown anywhere. One has to know the keyword to display them. Keywords can only be hidden at their creation

--primer - Makes a keyword a primer. Primer factoids are shown when a user talks to the bot the first time. Useful for FAQs.

NAME

~whatis - display factiods

SYNOPSIS

~whatis [ --verbose | --ksearch search-string-with-%-wildcards ] ( keyword | other-keyword | "just another keyword" )

DESCRIPTION

Only one long option is allowed at a time.

--verbose - Display also creating user and creation time.

--ksearch - Search for keywords. %-wildcards are implicit, so 'string' is '%string%', but '%string' or 'string%' are different.

TBD.

### Getting things up and running for development

(Provided you have a Ruby environment. If not, look [here](https://cbednarski.com/articles/installing-ruby/).)

* After cloning the repository you might want to install the necessary Gems:

  `bundle install`

* Create the database directory:

  `mkdir db`

* Start the bot:

  `ruby bot.rb`

* TBD

### Installing production-ready

TBD.

### Caveats
    
The first bot master has to be created manually in the SQL database.
In your SQLite client do `insert into users (discord_id, name, botmaster, enabled, created, changed) values (DISCORD_ID, 'DISCORD_NAME_W/O_THE_#_PART', 1, 1, UNIX_TIMESTAMP, UNIX_TIMESTAMP)`.

Check with `~user --list`.

The bot is not beeing translated yet and is only talking German.

### Remark
I tend to mix English and German language throughout the project.
Sorry for that.
