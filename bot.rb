#
# Morgoth
# A Discord bot for Star Citizen

# Copyright 2018 marcus@dankesuper.de

# This file is part of Morgoth.

# Morgoth is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# Morgoth is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with Morgoth.  If not, see <http://www.gnu.org/licenses/>.
#

require 'discordrb'
require 'json'
require 'sequel'

cfile = File.read('config.json')
config = JSON.parse(cfile)

DB = Sequel.connect('sqlite://db/bot.db')
DB.create_table? :users do
  primary_key :id
  Integer :discord_id
  String :name
  TrueClass :botmaster
  TrueClass :enabled
  Time :created
  Time :changed
end
DB.create_table? :keywords do
  primary_key :id
  String :name
  Integer :iduser
  Time :created
  Time :changed
end
DB.create_table? :definitions do
  primary_key :id
  String :definition, text: true
  Integer :idkeyword
  Time :created
  Time :changed
end

bot = Discordrb::Commands::CommandBot.new token: config['bot_token'], client_id: config['bot_client_id'], prefix: config['bot_prefix']

bot.command(:test) do |event|  
  #song = event.message.content.split(' ')[1]
  "*Ich funktioniere innerhalb definierter Parameter.*"
end

# merke/definiere --alias
# ~merke keyword/"mehrere begriffe"[mindestens ein space]definition des begriffs

# wasist --ordentlich/-o (sort a-z, sonst nach erstelldatum)
# ~wasist keyword/"mehrere begriffe"
# ausgabe mit nummern am ende in klammern

# vergiss
# ~vergiss keyword/"mehrere begriffe"

# wasisterw
# wie wasist, aber zusaetzlich mit ersteller und datum

# ueber
# ~ueber
# ausgabe von versionsnummer + link zum github
# uptime
# anzahl von eintraegen
# datum erster und letzter

bot.command(:user) do |event, *args|
  # recht zum aufruf pruefen
  user = DB[:users].where(discord_id: event.user.id, botmaster: true, enabled: true).first
  unless user
    event << "Nur Botmaster dürfen das!"
    return
  end

  cmd = args.shift

  # add
  if cmd == "--add"
    # gibt es den discord-user?
    new_user = {}
    bot.users.each do |u|
      if u[1].username.downcase == args[0].downcase
	new_user['username'] = u[1].username
	new_user['id'] = u[1].id
	break
      end
    end
    if new_user.empty?
      event << "Unbekannter Discord-User."
      return
    end

    # gibt es den user schon im bot?
    old_user = DB[:users].where(discord_id: new_user['id']).first
    if old_user
      event << "User schon vorhanden."
      return
    end

    if args[1]&.downcase == "botmaster"
      new_user['botmaster'] = 1
    else
      new_user['botmaster'] = 0
    end

    now = Time.now.to_i
    DB[:users].insert(
      discord_id: new_user['id'],
      name: new_user['username'],
      botmaster: new_user['botmaster'],
      enabled: 1,
      created: now,
      changed: now
    )

    event << "Erledigt."
    return

  # disable
  # gibt es den user, sonst meldung und ende
  # user sperren
  elsif cmd == "--disable"

  # list
  elsif cmd == "--list"
    en_users = DB[:users].where(enabled: true).order(:name)
    dis_users = DB[:users].where(enabled: false).order(:name)

    unless en_users.empty?
      event << "User:"
      en_users.each do |user|
	botmaster = user[:botmaster] ? ", Botmaster" : ""
	event << user[:name] + botmaster
      end
    end

    unless dis_users.empty?
      event << "Inaktive:"
      dis_users.each do |user|
	botmaster = user[:botmaster] ? ", Botmaster" : ""
	event << user[:name] + botmaster
      end
    end

  # falsches kommando
  else

  end

  "ENDE"
end

# undo
# ~undo
# ausgabe was rueckgaengig gemacht wurde oder fehler bei zeitueberschreitung

def shut_down(b)
  bot = b
  puts "Auf Wiedersehen!"
  bot.stop
end

Signal.trap('INT') { 
  shut_down(bot)
  exit
}

bot.run
