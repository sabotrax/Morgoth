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
require 'yaml'

require_relative 'helper'
require_relative 'ship'

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
  TrueClass :primer
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
DB.create_table? :templates do
  Integer :idkeyword, index: true
  String :object, text: true
  Time :created
  Time :changed
end
DB.create_table? :sightings do
  primary_key :id
  Integer :iduser
  Integer :discord_user_id
  Time :seen
end

bot = Discordrb::Commands::CommandBot.new token: config['bot_token'], client_id: config['bot_client_id'], prefix: config['bot_prefix'], help_command: [:hilfe, :help]

# Schreibt in die Begriffs-Datenbank.
# Nur Bot-User.
#
# Begriff Erklaerung
# Speichert Erklaerung unter Begriff.
#
# --alias Alias Begriff
# Legt einen Alias auf einen Begriff an.
#
# --primer Begriff true|false
# Fuegt Begriff zur Liste hinzu bzw. entfernt davon, die Benutzern beim ersten Aufruf des Bots angezeigt werden.
#
bot.command([:merke, :define], description: 'Trägt in die Begriffs-Datenbank ein.', usage: '~merke [ --alias Alias Begriff ] [ --primer Begriff ( true | false ) ] ( Begriff | Doppel-Begriff | "Ein erweiterter Begriff" ) Text der Erklärung') do |event, *args|
  # recht zum aufruf pruefen
  user = DB[:users].where(discord_id: event.user.id, enabled: true).first
  unless user
    event << "Nur Bot-User dürfen das!"
    return
  end

  seen(event, user)

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
    db_definition = DB[:keywords].select(:name).join(:definitions, :idkeyword => :id).where({Sequel.function(:upper, :definition) => definition.upcase})
    if db_definition.any?
      keyword_names = []
      db_definition.each do |k|
	keyword_names.push k[:name]
      end
      event << "Hinweis: Bereits definiert als #{keyword_names.join(', ')}."
    end

    # gibt es das keyword schon?
    old_keyword = DB[:keywords].where({Sequel.function(:upper, :name) => keyword.upcase}).first

    # hat das keyword eine zugeordnete vorlage?
    # falls ja, ist erste wort nach dem keyword ein attribut der vorlage?
    # falls nein, unten weiter
    # falls ja, objekt laden und typecheck durchfuehren
    # nicht ok -> fehlermeldung + ende
    # ok, dann neuen wert speichern, objekt schreiben

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

      # problem
      # "merke irgendwas laenge 30" weiss nicht, zu welchem template es gehoert, weil das attribut "laenge" zu mehreren gehoeren koennte, zb schiff und waffe
      # deswegen vorerst nur EIN template pro keyword
      db_template = DB[:templates].where(idkeyword: idkeyword).first

      # wenn ein template zugeordnet ist, dann hat dessen definition vorrang
      attribute = true
      if db_template
        object = YAML::load db_template[:object]

        begin
          object.fill targs

        # falsches/unbekanntes attribut
        # es koennte aber auch eine normale defintion sein,
        # deswegen unten weiter
        rescue TemplateArgumentError => e
          attribute = false

        # wert des attributs falsch
        rescue ArgumentError => e
          event.respond e.message
          return
        end

        if attribute
          sobject = YAML::dump(object)
          DB[:templates].where(idkeyword: db_template[:idkeyword]).update(object: sobject)
        end

      end

      # normale definition
      unless attribute
        DB[:definitions].insert(
	  definition: targs.join(' '),
	  iduser: user[:id],
	  idkeyword: idkeyword,
	  created: now,
	  changed: now
        )
      end
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
    link_keyword = DB[:keywords].where({Sequel.function(:upper, :name) => link.upcase}).first
    if link_keyword
      event << "Alias vorhanden."
      return
    end
    
    # ziel muss vorhanden sein, aber selbst kein alias
    target_keyword = DB[:keywords].where({Sequel.function(:upper, :name) => target.upcase}).first
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

  # primer
  elsif cmd == "--primer"
    unless user[:botmaster]
      event.respond 'Nur Bot-Master dürfen das!'
      return
    end

    if targs.size < 2 or targs[1] !~ /^(?:true|false)$/i
      event.respond 'Fehlerhafter Aufruf.'
      return
    end

    keyword = targs.shift || ""
    keyword.delete! "\""

    # begriff bekannt?
    db_keyword = DB[:keywords].where({Sequel.function(:upper, :name) => keyword.upcase}).first
    unless db_keyword
      event.respond 'Unbekannt.'
      return
    end

    # alias aufloesen
    id = db_keyword[:id]
    if db_keyword[:alias_id]
      event.respond 'Alias aufgelöst, --primer wird auf Original angewendet.'
      id = db_keyword[:alias_id]
    end

    if targs[0].downcase == 'true'
      action = true
    else
      action = false
    end
    DB[:keywords].where(id: id).update(primer: action)

    event.respond 'Erledigt.'

  # template
  elsif cmd == "--template"
    if targs.size < 3 or targs[2] !~ /^(?:true|false)$/i
      event.respond 'Fehlerhafter Aufruf.'
      return
    end

    unless targs[1] =~ /^ship$/i
      event.respond 'Unbekannte Vorlage.'
      return
    end

    keyword = targs.shift || ""
    keyword.delete! "\""

    db_keyword = DB[:keywords].where({Sequel.function(:upper, :name) => keyword.upcase}).first
    if db_keyword and db_keyword[:alias_id]
      event.respond 'Begriff ist Alias.'
      return
    end

    # hinweis
    # nur ein template pro keyword - im gegensatz zu unten
    if db_keyword and targs[1].downcase == 'true' and DB[:templates].where(idkeyword: db_keyword[:id]).first
      event.respond 'Vorlage bereits zugeordnet.'
      return
    end

    object = false
    if targs[0].downcase == 'ship'
      object = Ship.new
    end
    sobject = YAML::dump(object)

    # template anlegen
    if targs[1].downcase == 'true'
      now = Time.now.to_i

      # neues keyword + template
      unless db_keyword
        DB.transaction do
	  idkeyword = DB[:keywords].insert(
	    name: keyword,
	    iduser: user[:id],
	    created: now,
	    changed: now
	  )

          DB[:templates].insert(
            idkeyword: idkeyword,
            object: sobject,
            created: now,
            changed: now
          )
        end

      # keyword vorhanden, template dazu
      else
        DB[:templates].insert(
          idkeyword: db_keyword[:id],
          object: sobject,
          created: now,
          changed: now
        )
      end

    # template loeschen
    # hinweis
    # loeschen beachtet verschiedene templates pro keyword, dies wird aber nicht benutzt
    else
      if db_keyword

        # keyword hat definitionen
        if DB[:definitions].where(idkeyword: db_keyword[:id]).first
          DB[:templates].where(idkeyword: db_keyword[:id]).where(Sequel.ilike(:object, "--- !ruby/object:#{targs[0]}%")).delete

        # keyword mit template allein
        else
          DB.transaction do
            DB[:keywords].where(id: db_keyword[:id]).delete

            DB[:templates].where(idkeyword: db_keyword[:id]).where(Sequel.ilike(:object, "--- !ruby/object:#{targs[0]}%")).delete
          end
        end
      end
    end

    event.respond 'Erledigt.'

  # unbekanntes kommando
  else
    event << "Unbekanntes Kommando."
  end

end 

# Fragt die Begriffs-DB ab.
# Jeder.
#
# Begriff
# Sucht Definitionen zum Begriff.
#
# --bsuche Begriff mit %-Wildcards
# Fuehrt eine Like-Suche nach Begriffen durch.
# Der Suchstring kann mit %-Wildcards gebaut werden, z. B. %string, string%, %string%.
# Standard ist %string%.
#
bot.command([:wasist, :whatis], description: 'Fragt die Begriffs-Datenbank ab.', usage: '~wasist [--bsuche Suchtext-mit-%-Wildcards] ( Begriff | Doppel-Begriff | "Ein erweiterter Begriff" )') do |event, *args|
  seen(event)

  cmd = args.shift if args[0] =~ /^--/

  # tokenize nicht noetig bei abfragen (und macht die benutzung komplizierter)
  keyword = args.join(' ') || ''
  keyword.delete! "\""
  if keyword.empty?
    event << "Fehlerhafter Aufruf."
    return
  end

  if cmd.nil?
    # begriff bekannt?
    db_keyword = DB[:keywords].where({Sequel.function(:upper, :name) => keyword.upcase}).first
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

    # hinweis
    # fuer mehrere templates pro keyword vorbereitet, dies wird aber nicht benutzt
    template_set = DB[:templates].where(idkeyword: (db_keyword[:alias_id] || db_keyword[:id]))
    template_set.each do |template|
      object = YAML::load template[:object]
      event << object.formatter
    end

    i = 0
    definition_set.order(:created).each do |definition|
      event << "#{definition[:definition]} (#{i += 1})"
    end

  elsif cmd == "--bsuche"
    if keyword.length < 3
      event << "Suchbegriff zu kurz. Drei Zeichen bitte."
      return
    elsif keyword !~ /%/
      keyword = '%' + keyword + '%'
    end

    # begriff bekannt?
    db_keywords = DB[:keywords].where(Sequel.ilike(:name, keyword)).order(:name)
    unless db_keywords.any?
      event << "Unbekannt."
      return
    end

    # ausgabe aufbereiten
    kw_names = []
    db_keywords.each do |db_k|

      # aliase aufloesen
      if db_k[:alias_id]
	db_orig_keyword = DB[:keywords].where(id: db_k[:alias_id]).first

	# bei alias auch original anzeigen
	kw_names.push "#{db_k[:name]} (#{db_orig_keyword[:name]})"

      else
	kw_names.push db_k[:name]
      end

    end

    # ausgeben
    formatter(kw_names).each {|line| event.respond line }

  # unbekanntes kommando
  else
    event << "Unbekanntes Kommando."
  end

  return

end

# Loescht aus der Begriffs-Datenbank.
# Nur Bot-User.
#
# Begriff Ziffer
# Löscht Erklaerung unter Angabe der Ziffer aus wasist.
#
bot.command([:vergiss, :undefine], description: 'Löscht aus der Begriffs-Datenbank.', usage: '~vergiss ( Begriff | Doppel-Begriff | "Ein erweiterter Begriff" ) Klammer-Ziffer aus ~wasist') do |event, *args|
  # recht zum aufruf pruefen
  user = DB[:users].where(discord_id: event.user.id, enabled: true).first
  unless user
    event << "Nur Bot-User dürfen das!"
    return
  end

  seen(event, user)

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
      event << "Ziffer fehlt."
      return
    end

    # begriff bekannt?
    db_keyword = DB[:keywords].where({Sequel.function(:upper, :name) => keyword.upcase}).first
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

    # sind diesem begriff templates zugeordnet?
    db_template = DB[:templates].where(idkeyword: (db_keyword[:alias_id] || db_keyword[:id])).first

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

	# nur ein eintrag und keine templates: keyword, aliase und eintrag loeschen
	if definition_set.count == 1 and ! db_template
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
  seen(event)

  event << "v#{config['version']} #{config['website']}"
  event << "#{DB[:users].count} Benutzer"
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

  seen(event, user)

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
    target_user = DB[:users].where({Sequel.function(:upper, :name) => duser.upcase}).first
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
    target_user = DB[:users].where({Sequel.function(:upper, :name) => duser.upcase}).first
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

# Zeigt Begriffe mit neuen Erklaerungen.
# Jeder.
#
bot.command([:neueste, :latest], description: 'Zeigt die neuesten Einträge der Begriffs-Datenbank.', usage: '~neueste') do |event, *args|
  seen(event)

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

  # ausgeben
  formatter(seen_keywords).each {|line| event.respond line }

  return

end

# Wuerfelt mit verschiedenen Wuerfeln.
# Jeder.
#
# Anzahl der Wuerfe mal Seitenzahl.
# Standard ist 1d6.
#
bot.command([:wuerfeln, :roll], description: 'Würfelt bis 9d999.', usage: '~wuerfeln [ 1-9 ( d | w ) 1-999 ]') do |event, *args|
  seen(event)

  args.push '1d6' unless args.any?
  unless args[0] =~ /^([1-9])(?:(?:d|w)([1-9]\d{,2}))?$/
    event << "Fehlerhafter Aufruf."
    return
  end
  anzahl = $1.to_i
  seiten = $2 || 6

  erg = []
  rng = Random.new
  (1..anzahl).each do |i|
    erg.push '.' * (rand(6) + 1)
    erg.push rng.rand(seiten.to_i) + 1
  end

  event.respond ':game_die:' + erg * ' '

  return
end

# Fragt die Datenbank mit einem zufaelligen Begriff ab.
#
bot.command([:zufaellig, :random], description: 'Zeigt einen zufälligen Begriff.', usage: '~zufaellig') do |event, *args|
  seen(event)

  db_keyword = DB[:keywords].order(Sequel.lit('RANDOM()')).first
  unless db_keyword
    event.respond "Es gibt keine Einträge."
    event.respond "Das ist ein bisschen traurig."
    return
  end

  bot.execute_command(:wasist, event, [ db_keyword[:name] ])
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
