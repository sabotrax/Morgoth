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

The bot's primary job is to store and display factoids.

A factoid is made up of a keyword and some text.

Everybody on the Discord can execute non-writing bot commands.

Only users known to the bot can execute writing commands.

Users known as bot masters can elevate others.

Commands:

NAME

~define - store factiods

SYNOPSIS

~define [ --alias alias keyword ] [ --hidden ] [ --primer keyword ( true | false ) ] ( keyword | other-keyword | "just another keyword" ) text

DESCRIPTION

Only one long option is allowed at a time.

--alias

  Creates an alias to the keyword

--hidden

  Creates a hidden keyword. Hidden keywords are not shown anywhere. One has to know the keyword to display them. Keywords can only be hidden at their creation

--primer

  Makes a keyword a primer. Primer factoids are shown when a user talks to the bot the first time. Useful for FAQs.

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

### Remark
I tend to mix English and German language throughout the project.
Sorry for that.
