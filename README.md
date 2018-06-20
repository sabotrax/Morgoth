# Morgoth
## A Discord bot for Star Citizen

### What it is

Morgoth is an information-storing Discord bot and general source of fun.

Features:

* Remember and recall factoids (which are just keyword/text combos).
* Search, show latest and display random keywords.
* Create aliases and hashtags.
* User management.
* Greeting new users with configurable in-bot messages.
* Download the bot's database on the fly.
* Rolling dice.

Examples:

~define "Dwarf Fortress" If you like great games and ASCII chars, then this is it.

~define --alias DF "Dwarf Fortress"

~define df #games

~whatis df  
DF (Dwarf Fortress)  
If you like great games and ASCII chars, then this is it. (1)  
#games (2)

~whatis #games  
Dwarf Fortress

~undefine df 2

~define df #greatgames

### Documentation

Overview:

The bot's primary job is to store and display factoids. A factoid is made up of a keyword and some text.  
Everybody on the Discord server can execute non-writing bot commands, like asking the bot about stuff.  
Only users known to the bot can execute writing commands, like adding new stuff or creating aliases.  
Users known as bot masters can elevate others.

Commands:

NAME

**~define - store factiods**

SYNOPSIS

~define ( ( keyword | other-keyword | "just another" ) text | [ --alias alias keyword | --hidden | --primer keyword ( true | false ) | --pin keyword number ] )

DESCRIPTION

Only one option is allowed at a time.

--alias - Creates an alias to the keyword

--hidden - Creates a hidden keyword. Hidden keywords are not shown anywhere. One has to know the keyword to display them. Keywords can only be hidden at their creation

--primer - Makes a keyword a primer. Primer factoids are shown when a user talks to the bot the first time. Useful for FAQs.

--pin - Normally factoids are ordered by date of creation. A pinned entry is shown first. Only one entry can be pinned.

NAME

**~whatis - display factiods**

SYNOPSIS

~whatis ( [ --verbose ] ( keyword | other-keyword | "just another" ) | --ksearch %-wildcarded-search-string | #hashtag )

DESCRIPTION

Only one option is allowed at a time.
When asked for a keyword, ~whatis is displaying the keyword and its factoids.
When used with --ksearch or a hashtag, it's showing keywords only.

--verbose - Also show alias, creator and timestamp.

--ksearch - Search for keywords. %-wildcards are implicit, so 'string' is '%string%', but '%string' or 'string%' are different.

NAME

**~undefine - delete factoids**

SYNOPSIS

~undefine ( ( keyword | other-keyword | "just another" ) factoid-identifying numeral | ( --alias | --pin ) ( keyword | other-keyword | "just another" ) )

DESCRIPTION

Only one option is allowed at a time.
The factiod-identifying numeral is the digit that is beeing displayed in parentheses right after the factoid when using ~whatis.

--alias - Deletes an alias.

--pin - Removes the factoid's accentuation.

TBD.

### Getting things up and running for development

(Provided you have a Ruby environment. If not, look [here](https://cbednarski.com/articles/installing-ruby/).)

* After cloning the repository you might want to cd into the directory and install the necessary Gems:

  `bundle install`

* Create the database directory:

  `mkdir db`

* Start the bot:

  `ruby bot.rb`

* TBD

### Installing production-ready

TBD.

### Caveats

The bot is not beeing translated yet and is only talking German.

### Remark
I tend to mix English and German language throughout the project.
Sorry for that.
