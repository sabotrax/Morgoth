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

# argumente in anfuehrungszeichen gruppieren
def tokenize(args)
  args.join(' ').scan(/(?:"[^"]+"|[^\s]+)/)
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

  targs = tokenize(args)

  if cmd.nil?
    keyword = targs.shift
    keyword.delete! '"'
    if targs.empty?
      event << "Fehlerhafter Aufruf."
      return
    end

    # hinweis auf mehrfache definitionen
    definition = targs.join(' ')
    db_definition = DB[:keywords].select(:name).join(:definitions, :idkeyword => :id).where(Sequel.ilike(:definition, definition))
    if db_definition
      keyword_names = []
      db_definition.each do |k|
	keyword_names.push k[:name]
      end
      event << "Hinweis: Bereits definiert als #{keyword_names.join(', ')}."
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

      # alias aufloesen
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

  targs = tokenize(args)

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
    db_orig_keyword = DB[:keywords].where(id: db_keyword[:alias_id]).first
    definition_set = DB[:definitions].where(idkeyword: db_keyword[:alias_id])
  else
    definition_set = DB[:definitions].where(idkeyword: db_keyword[:id])
  end

  # bei alias auch original zeigen
  if db_orig_keyword
    event << "**#{db_keyword[:name]} (#{db_orig_keyword[:name]}):**"
  else
    event << "**#{db_keyword[:name]}:**"
  end

  i = 0
  definition_set.order(:created).each do |definition|
    event << "#{definition[:definition]} (#{i += 1})"
  end

  return
end

# vergiss --alias
bot.command([:vergiss, :undefine], description: 'Löscht aus der Begriffs-Datenbank.', usage: '~vergiss ( Begriff | Doppel-Begriff | "Ein erweiterter Begriff" ) Klammer-Ziffer aus ~wasist') do |event, *args|
  # recht zum aufruf pruefen
  user = DB[:users].where(discord_id: event.user.id, enabled: true).first
  unless user
    event << "Nur Bot-User dürfen das!"
    return
  end

  cmd = args.shift if args[0] =~ /^--/

  targs = tokenize(args)

  keyword = targs.shift || ""
  keyword.delete! "\""
  if keyword.empty?
    event << "Fehlerhafter Aufruf."
    return
  end

  if cmd.nil?
    # bezeichner des zu loeschenden eintrags vorhanden?
    if targs[0] !~ /^\d+$/
      event << "Ziffer nicht vorhanden."
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

    # zu loeschenden eintrag finden
    i = 0
    db_definition = {}
    definition_set.order(:created).each do |definition|
      i += 1
      if targs[0].to_i == i
	db_definition = definition
	break
      end
    end
    if db_definition.empty?
      event << "Unbekannte Ziffer."
      return
    end

    # zur abfrage darstellen, eventuell verkuerzt
    token = db_definition[:definition].split(/ /)
    db_definition[:definition] = token[0] + ' .. ' + token[-1] if token.size > 3
    event.respond "Eintrag \"#{db_definition[:definition]}\" wirklich löschen? (j/n)"

    # sicherheitsabfrage
    event.user.await(:wirklich) do |wirklich_event|
      if wirklich_event.message.content.downcase == "j"

	# nur ein eintrag: keyword, aliase und eintrag loeschen
	if definition_set.count == 1
	  DB.transaction do
	    DB[:keywords].where(id: db_definition[:idkeyword]).or(alias_id: db_definition[:idkeyword]).delete
	    definition_set.delete
	  end

	# mehrere: eintrag loeschen
	else
	  definition_set.where(id: db_definition[:id]).delete
	end

	wirklich_event.respond "Erledigt."
      else
	wirklich_event.respond "Dann nicht."
      end
    end

    return

  elsif cmd == "--alias"

  # unbekanntes kommando
  else
    event << "Unbekanntes Kommando."
  end

end

# Bot-Info
# Jeder.
#
bot.command([:ueber, :about], description: 'Nennt Bot-Infos.') do |event, *args|
  event << "v#{config['version']} #{config['website']}"
  event << "#{DB[:users].count} Benutzer"
  #event << "#{DB[:keywords].where(alias_id: nil).count} Begriffe und #{DB[:keywords].exclude(alias_id: nil, id: 7000).count} Aliase"
  event << "#{DB[:keywords].where(alias_id: nil).count} Begriffe und #{DB[:keywords].exclude(alias_id: nil).count} Aliase"
  event << "#{DB[:definitions].count} Erklärungen"
end

# Benutzerverwaltung
# Nur fuer Botmaster.
#
# --add Discord-User [Botmaster]
# Fuegt Benutzer zum Bot hinzu.
# "Botmaster" legt Benutzer als Botmaster an.
#
# --enable Discord-User
# Aktiviert Benutzer.
# Nur aktive Benutzer koennen schreibend auf die Begriffs-DB zugreifen.
# Standard nach Anlegen.
#
# --disable Discord-User
# Setzt Benutzer inaktiv.
# Kann nicht auf Botmaster angewandt werden.
#
# --botmaster Discord-User
# Macht Benutzer zum Botmaster.
#
# --list
# Listet Bot-Benutzer auf.
#
bot.command(:user, description: 'Regelt Benutzer-Rechte. Nur Botmaster.', usage: '~user --list | --add  Discord-User [Botmaster] | ( --enable | --disable  | --botmaster Discord-User )') do |event, *args|
  # recht zum aufruf pruefen
  user = DB[:users].where(discord_id: event.user.id, botmaster: true, enabled: true).first
  unless user
    event << "Nur Botmaster dürfen das!"
    return
  end

  cmd = args.shift

  targs = tokenize(args)

  # add
  if cmd == "--add"
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
  elsif cmd =~ /^--(enable|disable)$/
    duser = targs.shift || ""
    duser.delete! "\""
    if duser.empty?
      event << "Fehlerhafter Aufruf."
      return
    end

    # gibt es den user im bot?
    target_user = DB[:users].where(Sequel.ilike(:name, duser)).first
    unless target_user
      event << "User nicht vorhanden."
      return
    end

    # user darf kein botmaster sein
    if target_user[:botmaster]
      event << "User darf kein Botmaster sein."
      return
    end

    if cmd == "--enable"
      enabled = true
    else
      enabled = false
    end

    DB[:users].where(id: target_user[:id]).update(enabled: enabled)

    event << "Erledigt."

  # botmaster
  elsif cmd == "--botmaster"
    duser = targs.shift || ""
    duser.delete! "\""
    if duser.empty?
      event << "Fehlerhafter Aufruf."
      return
    end

    # gibt es den user im bot?
    target_user = DB[:users].where(Sequel.ilike(:name, duser)).first
    unless target_user
      event << "User nicht vorhanden."
      return
    end

    DB[:users].where(id: target_user[:id]).update(botmaster: true)

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

# neueste --alias - soll aliase zeigen
bot.command([:neueste, :latest], description: 'Zeigt die neuesten Einträge der Begriffs-Datenbank.', usage: '~neueste') do |event, *args|
  dataset = DB[:keywords].select(:name).join(:definitions, :idkeyword => :id).reverse_order(Sequel[:definitions][:created]).limit(config['show_latest_definitions'] + 50)

  event.respond "**Die neuesten Einträge:**"

  unless dataset.count > 0
    event.respond "Keine."
    event.respond "Das ist ein bisschen traurig."
    return
  end

  # doppelte keywords aussortieren
  seen_keywords = []
  dataset.each do |entry|
    break if seen_keywords.size == config['show_latest_definitions']
    if seen_keywords.include? entry[:name]
      next
    else
      seen_keywords.push entry[:name]
    end
  end

  # in zeilen zu fuenf ausgeben
  keywords = []
  i = 0
  seen_keywords.each do |keyword|
    keywords.push keyword
    i += 1
    if i % 5 == 0
      event.respond keywords.join(', ')
      keywords.clear
    elsif i == seen_keywords.size
      event.respond keywords.join(', ')
    end
  end

  return

end

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
