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
  Integer :alias_id
  Time :created
  Time :changed
end
DB.create_table? :definitions do
  primary_key :id
  String :definition, text: true
  Integer :iduser
  Integer :idkeyword
  Time :created
  Time :changed
end

bot = Discordrb::Commands::CommandBot.new token: config['bot_token'], client_id: config['bot_client_id'], prefix: config['bot_prefix'], help_command: [:hilfe, :help]

bot.command([:merke, :define], description: 'Trägt in die Begriffs-Datenbank ein.', usage: '~merke [ --alias Alias Begriff ] ( Begriff | Doppel-Begriff | "Ein erweiterter Begriff" ) Text der Erklärung') do |event, *args|
  # recht zum aufruf pruefen
  user = DB[:users].where(discord_id: event.user.id, enabled: true).first
  unless user
    event << "Nur Bot-User dürfen das!"
    return
  end

  cmd = args.shift if args[0] =~ /^--/

  # argumente in anfuehrungszeichen gruppieren
  arg_string = args.join(' ')
  targs = arg_string.scan(/(?:[-\w]|"[^"]*")+/)

  if cmd.nil?
    keyword = targs.shift
    keyword.delete! '"'
    if targs.empty?
      event << "Fehlerhafter Aufruf."
      return
    end

    # gibt es das keyword schon?
    old_keyword = DB[:keywords].where(Sequel.ilike(:name, keyword)).first

    now = Time.now.to_i
    # neues keyword + eintrag
    unless old_keyword
      DB.transaction do
	idkeyword = DB[:keywords].insert(
	  name: keyword,
	  iduser: user[:id],
	  created: now,
	  changed: now
	)

	DB[:definitions].insert(
	  definition: targs.join(' '),
	  iduser: user[:id],
	  idkeyword: idkeyword,
	  created: now,
	  changed: now
	)
      end

    # weiterer eintrag zum vorhandenen keyword
    else

      # unter original speichern
      if old_keyword[:alias_id]
	idkeyword = old_keyword[:alias_id]
      else
	idkeyword = old_keyword[:id]
      end

      DB[:definitions].insert(
	definition: targs.join(' '),
	iduser: user[:id],
	idkeyword: idkeyword,
	created: now,
	changed: now
      )
    end

    event << "Erledigt."

  # alias
  elsif cmd == "--alias"
    if targs.size < 2
      event << "Fehlerhafter Aufruf."
      return
    end

    link = targs.shift
    link.delete! '"'
    target = targs.shift
    target.delete! '"'

    # alias darf nicht vorhanden sein
    link_keyword = DB[:keywords].where(Sequel.ilike(:name, link)).first
    if link_keyword
      event << "Alias vorhanden."
      return
    end
    
    # ziel muss vorhanden sein, aber selbst kein alias
    target_keyword = DB[:keywords].where(Sequel.ilike(:name, target)).first
    unless target_keyword
      event << "Ziel-Begriff nicht vorhanden."
      return
    end
    if target_keyword[:alias_id]
      event << "Ziel-Begriff ist Alias."
      return
    end

    now = Time.now.to_i
    DB[:keywords].insert(
      name: link,
      iduser: user[:id],
      alias_id: target_keyword[:id],
      created: now,
      changed: now
    )

    event << "Erledigt."

  # unbekanntes kommando
  else
    event << "Unbekanntes Kommando."
  end

end 

# wasist --ordentlich/-o (sort a-z, sonst nach erstelldatum)
# wasist --alles/-a erweiterte ausgabe mit ersteller, datum, aliasen
bot.command([:wasist, :whatis], description: 'Fragt die Begriffs-Datenbank ab.', usage: '~wasist ( Begriff | Doppel-Begriff | "Ein erweiterter Begriff" )') do |event, *args|
  cmd = args.shift if args[0] =~ /^--/

  # argumente in anfuehrungszeichen gruppieren
  arg_string = args.join(' ')
  targs = arg_string.scan(/(?:[-\w]|"[^"]*")+/)

  keyword = targs.shift || ""
  keyword.delete! "\""
  if keyword.empty?
    event << "Fehlerhafter Aufruf."
    return
  end

  # begriff bekannt?
  db_keyword = DB[:keywords].where(Sequel.ilike(:name, keyword)).first
  unless db_keyword
    event << "Unbekannt."
    return
  end

  # alias aufloesen
  if db_keyword[:alias_id]
    definition_set = DB[:definitions].where(idkeyword: db_keyword[:alias_id])
  else
    definition_set = DB[:definitions].where(idkeyword: db_keyword[:id])
  end

  event << "**#{db_keyword[:name]}:**"
  i = 0
  definition_set.order(:created).each do |definition|
    event << "#{definition[:definition]} (#{i += 1})"
  end

  return
end

# vergiss
# ~vergiss keyword/"mehrere begriffe"

# ueber
# ~ueber
# uptime
# datum erster und letzter
bot.command([:ueber, :about], description: 'Nennt Bot-Infos.') do |event, *args|
  event << "v#{config['version']} #{config['website']}"
  event << "#{DB[:users].count} Benutzer"
  event << "#{DB[:keywords].count} Begriffe"
  event << "#{DB[:definitions].count} Erklärungen"
end

# ~user --botmaster
bot.command(:user, description: 'Regelt Benutzer-Rechte.', usage: '~user ( --add Discord-User | --disable Discord-User | --list )') do |event, *args|
  # recht zum aufruf pruefen
  user = DB[:users].where(discord_id: event.user.id, botmaster: true, enabled: true).first
  unless user
    event << "Nur Botmaster dürfen das!"
    return
  end

  cmd = args.shift

  # add
  if cmd == "--add"
    # argumente in anfuehrungszeichen gruppieren
    arg_string = args.join(' ')
    targs = arg_string.scan(/(?:[-\w]|"[^"]*")+/)

    duser = targs.shift || ""
    duser.delete! "\""
    if duser.empty?
      event << "Fehlerhafter Aufruf."
      return
    end

    # gibt es den discord-user?
    new_user = {}
    bot.users.each do |u|
      if u[1].username.downcase == duser.downcase
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

  # disable
  elsif cmd == "--disable"
    # TODO
    # abfrage und leerzeichen wie bei --add

    # gibt es den user im bot?
    target_user = DB[:users].where(Sequel.ilike(:name, args[0])).first
    unless target_user
      event << "User nicht vorhanden."
      return
    end

    # user darf kein botmaster sein
    if target_user[:botmaster]
      event << "User darf kein Botmaster sein."
      return
    end

    DB[:users].where(id: target_user[:id]).update(enabled: 0)

    event << "Erledigt."

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

    if en_users.empty? and dis_users.empty?
      event << "Keine User."
    end

  # falsches kommando
  else
    event << "Unbekanntes Kommando."
  end

end

# undo
# ~undo
# ausgabe was rueckgaengig gemacht wurde oder fehler bei zeitueberschreitung

# neueste
# ausgabe letzte x keywords

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
