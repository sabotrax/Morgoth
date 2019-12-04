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

require "discordrb"
require "sequel"
require "yaml"
require "rufus/scheduler"
require "adsf"
require "securerandom"
require "zlib"
require "net/http"

require_relative "helper"
require_relative "ship"
require_relative "config"

include Config

DB = Sequel.connect("sqlite://db/bot.db")
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
  TrueClass :hidden
  Time :created
  Time :changed
end
DB.create_table? :definitions do
  primary_key :id
  String :definition, text: true
  Integer :iduser
  Integer :idkeyword
  TrueClass :pinned
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
DB.create_table? :actions do
  primary_key :id
  Integer :iduser
  String :action
  String :payload, text: true
  TrueClass :applied, default: false
  String :created
end
DB.create_table? :diaries do
  primary_key :id
  Integer :iduser
  String :entry, text: true
  Time :created
  Time :changed
end

bot = Discordrb::Commands::CommandBot.new token: get_bot_token, client_id: get_bot_client_id, prefix: get_bot_prefix, help_command: [:hilfe, :help]

# Schreibt in die Begriffs-Datenbank.
# Nur Bot-User.
#
# Begriff Erklaerung
# Speichert Erklaerung unter Begriff.
#
# --alias Alias Begriff
# Legt einen Alias auf einen Begriff an.
#
# --hidden
# Legt einen versteckten Eintrag an.
# Dieser wird nicht gefunden von ~neueste, ~zufaellig, --bsuche, ~ueber.
#
# --primer Begriff true|false
# Fuegt Begriff zur Liste hinzu bzw. entfernt davon, die Benutzern beim ersten Aufruf des Bots angezeigt werden.
#
# --pin Begriff Ziffer
# Pinnt Eintrag des Begriffs unter Angabe der Ziffer aus ~wasist.
#
bot.command([:merke, :define], description: "Trägt in die Begriffs-Datenbank ein.", usage: '~merke ( ( Begriff | Doppel-Begriff | "Ein erweiterter Begriff" ) Text der Erklärung | [ --alias Alias Begriff | --hidden | --primer Begriff ( true | false ) | --pin Begriff Klammer-Ziffer aus ~wasist ] )') do |event, *args|
  # channel pruefen
  return unless listening_here(event)

  # recht zum aufruf pruefen
  user = DB[:users].where(discord_id: event.user.id, enabled: true).first
  unless user
    event.respond "Nur Bot-User dürfen das!"
    return
  end

  seen(event, user)

  cmd = args.shift if args[0] =~ /^--/

  targs = tokenize(args)

  if cmd.nil? or cmd == "--hidden"
    keyword = targs.shift
    keyword.delete! '"'
    if targs.empty?
      event.respond "Fehlerhafter Aufruf."
      return
    end
    if keyword =~ /^#/
      event.respond "Begriffe können keine Hashtags sein."
      return
    end

    # gibt es das keyword schon?
    old_keyword = DB[:keywords].where({ Sequel.function(:upper, :name) => Sequel.function(:upper, keyword) }).first
    if old_keyword and cmd == "--hidden"
      event.respond "Kann nur neue Einträge verstecken."
      return
    end

    # hinweis auf mehrfache definitionen
    definition = targs.join(" ")
    db_definition = DB[:keywords].select(:name).join(:definitions, :idkeyword => :id).where({ Sequel.function(:upper, :definition) => Sequel.function(:upper, definition) }).where(hidden: false)
    if db_definition.any?
      keyword_names = []
      db_definition.each do |k|
        keyword_names.push k[:name]
      end
      event << "Hinweis: bereits definiert als"
      formatter(keyword_names).each { |line| event << line }
    end

    now = Time.now.to_i
    # neues keyword + eintrag
    unless old_keyword
      DB.transaction do
        id_kw = idkeyword = DB[:keywords].insert(
          name: keyword,
          iduser: user[:id],
          hidden: cmd == "--hidden" ? true : false,
          created: now,
          changed: now,
        )

        id_df = DB[:definitions].insert(
          definition: targs.join(" "),
          iduser: user[:id],
          idkeyword: idkeyword,
          pinned: false,
          created: now,
          changed: now,
        )

        # fuer undo merken
        action = [
          [:keywords, id_kw, keyword, user[:id], cmd == "--hidden" ? true : false, now, now],
          [:definitions, id_df, targs.join(" "), user[:id], idkeyword, false, now, now],
        ]
        DB[:actions].insert(
          iduser: user[:id],
          action: "insert",
          payload: YAML::dump(action),
          created: now,
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
          DB.transaction do
            # fuer undo merken
            db_data = DB[:templates].where(idkeyword: db_template[:idkeyword]).first
            action = [
              [:templates, db_data[:idkeyword], db_data[:object], db_data[:created], db_data[:changed]],
            ]
            DB[:actions].insert(
              iduser: user[:id],
              action: "update",
              payload: YAML::dump(action),
              created: now,
            )

            sobject = YAML::dump(object)
            DB[:templates].where(idkeyword: db_template[:idkeyword]).update(object: sobject, changed: now)
          end
        end
      end

      # normale definition
      unless db_template and attribute
        DB.transaction do
          id = DB[:definitions].insert(
            definition: targs.join(" "),
            iduser: user[:id],
            idkeyword: idkeyword,
            pinned: false,
            created: now,
            changed: now,
          )

          # fuer undo merken
          action = [
            [:definitions, id, targs.join(" "), user[:id], idkeyword, false, now, now],
          ]
          DB[:actions].insert(
            iduser: user[:id],
            action: "insert",
            payload: YAML::dump(action),
            created: now,
          )
        end
      end
    end

    event << "Erledigt."

    # alias
  elsif cmd == "--alias"
    if targs.size < 2
      event.respond "Fehlerhafter Aufruf."
      return
    end

    link = targs.shift
    link.delete! '"'
    target = targs.shift
    target.delete! '"'

    # alias darf nicht vorhanden sein
    link_keyword = DB[:keywords].where({ Sequel.function(:upper, :name) => Sequel.function(:upper, link) }).first
    if link_keyword
      event.respond "Alias bereits vorhanden."
      return
    end

    # ziel muss vorhanden sein, aber selbst kein alias
    target_keyword = DB[:keywords].where({ Sequel.function(:upper, :name) => Sequel.function(:upper, target) }).first
    unless target_keyword
      event.respond "Ziel-Begriff nicht vorhanden."
      return
    end
    if target_keyword[:alias_id]
      event.respond "Ziel-Begriff ist Alias, aber muss Begriff sein."
      return
    end

    now = Time.now.to_i

    DB.transaction do
      id_kw = DB[:keywords].insert(
        name: link,
        iduser: user[:id],
        alias_id: target_keyword[:id],
        hidden: target_keyword[:hidden] == true ? true : false,
        created: now,
        changed: now,
      )

      # fuer undo merken
      action = [
        [:keywords, id_kw, link, user[:id], target_keyword[:hidden] == true ? true : false, now, now],
      ]
      DB[:actions].insert(
        iduser: user[:id],
        action: "insert",
        payload: YAML::dump(action),
        created: now,
      )
    end

    event.respond "Erledigt."

    # primer
  elsif cmd == "--primer"
    unless user[:botmaster]
      event.respond "Nur Bot-Master dürfen das!"
      return
    end

    if targs.size < 2 or targs[1] !~ /^(?:true|false)$/i
      event.respond "Fehlerhafter Aufruf."
      return
    end

    keyword = targs.shift || ""
    keyword.delete! "\""

    # begriff bekannt?
    db_keyword = DB[:keywords].where({ Sequel.function(:upper, :name) => Sequel.function(:upper, keyword) }).first
    unless db_keyword
      event.respond "Unbekannt."
      return
    end
    if db_keyword[:hidden]
      event.respond "Begriff darf nicht versteckt sein."
      return
    end

    # alias aufloesen
    id = db_keyword[:id]
    if db_keyword[:alias_id]
      event.respond "Hinweis: Alias aufgelöst, --primer wird auf Original angewendet."
      id = db_keyword[:alias_id]
    end

    if targs[0].downcase == "true"
      primer = true
    else
      primer = false
    end

    DB.transaction do
      # fuer undo merken
      db_data = DB[:keywords].where(id: id).first
      action = [
        [:keywords, db_data[:id], db_data[:name], db_data[:iduser], db_data[:alias_id], db_data[:primer], db_data[:hidden], db_data[:created].to_i, db_data[:changed].to_i],
      ]
      DB[:actions].insert(
        iduser: user[:id],
        action: "update",
        payload: YAML::dump(action),
        created: Time.now.to_i,
      )

      DB[:keywords].where(id: id).update(primer: primer)
    end

    event.respond "Erledigt."

    # template
  elsif cmd == "--template"
    if targs.size < 3 or targs[2] !~ /^(?:true|false)$/i
      event.respond "Fehlerhafter Aufruf."
      return
    end

    unless targs[1] =~ /^ship$/i
      event.respond "Unbekannte Vorlage."
      return
    end

    keyword = targs.shift || ""
    keyword.delete! "\""

    db_keyword = DB[:keywords].where({ Sequel.function(:upper, :name) => Sequel.function(:upper, keyword) }).first
    if db_keyword and db_keyword[:alias_id]
      event.respond "Begriff ist Alias, aber muss Begriff sein."
      return
    end

    # hinweis
    # nur ein template pro keyword - im gegensatz zu unten
    if db_keyword and targs[1].downcase == "true" and DB[:templates].where(idkeyword: db_keyword[:id]).first
      event.respond "Vorlage bereits zugeordnet."
      return
    end

    object = false
    if targs[0].downcase == "ship"
      object = Ship.new
    end
    sobject = YAML::dump(object)

    # template anlegen
    if targs[1].downcase == "true"
      now = Time.now.to_i

      # neues keyword + template
      # TODO
      # in undo aufnehmen
      unless db_keyword
        DB.transaction do
          idkeyword = DB[:keywords].insert(
            name: keyword,
            iduser: user[:id],
            hidden: false,
            created: now,
            changed: now,
          )

          DB[:templates].insert(
            idkeyword: idkeyword,
            object: sobject,
            created: now,
            changed: now,
          )
        end

        # keyword vorhanden, template dazu
        # TODO
        # in undo aufnehmen
      else
        DB[:templates].insert(
          idkeyword: db_keyword[:id],
          object: sobject,
          created: now,
          changed: now,
        )
      end

      # template loeschen
      # hinweis
      # loeschen beachtet verschiedene templates pro keyword, dies wird aber nicht benutzt
    else
      if db_keyword

        # keyword hat definitionen
        # TODO
        # in undo aufnehmen
        if DB[:definitions].where(idkeyword: db_keyword[:id]).first
          DB[:templates].where(idkeyword: db_keyword[:id]).where(Sequel.ilike(:object, "--- !ruby/object:#{targs[0]}%")).delete

          # keyword mit template allein
          # TODO
          # in undo aufnehmen
        else
          DB.transaction do
            DB[:keywords].where(id: db_keyword[:id]).delete

            DB[:templates].where(idkeyword: db_keyword[:id]).where(Sequel.ilike(:object, "--- !ruby/object:#{targs[0]}%")).delete
          end
        end
      end
    end

    event.respond "Erledigt."

    # pin
  elsif cmd == "--pin"
    if targs.size < 2 or targs[1] !~ /^[1-9]\d?$/i
      event.respond "Fehlerhafter Aufruf."
      return
    end

    keyword = targs.shift || ""
    keyword.delete! "\""

    # begriff bekannt?
    db_keyword = DB[:keywords].where({ Sequel.function(:upper, :name) => Sequel.function(:upper, keyword) }).first
    unless db_keyword
      event.respond "Unbekannt."
      return
    end
    if db_keyword[:hidden]
      event.respond "Begriff darf nicht versteckt sein."
      return
    end

    # alias aufloesen
    if db_keyword[:alias_id]
      definition_set = DB[:definitions].where(idkeyword: db_keyword[:alias_id])
    else
      definition_set = DB[:definitions].where(idkeyword: db_keyword[:id])
    end

    # zu pinnenden eintrag finden
    i = 0
    db_definition = {}
    db_pinned_definition = {}
    definition_set.reverse_order(:pinned).order(:created).each do |definition|
      i += 1
      if targs[0].to_i == i
        db_definition = definition
      end
      if definition[:pinned] == true
        db_pinned_definition = definition
      end
    end
    if db_definition.empty?
      event.respond "Unbekannte Ziffer."
      return
    end

    # auf alias hinweisen
    if db_keyword[:alias_id]
      event.respond "Hinweis: Alias aufgelöst, --pin wird auf Original angewendet."
    end
    # auf bereits gepinnten eintrag hinweisen
    if db_pinned_definition.any?
      token = db_pinned_definition[:definition].split(/ /)
      db_pinned_definition[:definition] = token[0] + " .. " + token[-1] if token.size > 3
      event.respond "Hinweis: Gepinnter Eintrag \"#{db_pinned_definition[:definition]}\" wird überschrieben."
    end

    DB.transaction do
      # fuer undo merken
      action = []
      if db_pinned_definition.any?
        db_data = DB[:definitions].where(id: db_pinned_definition[:id]).first
        action.push [:definitions, db_data[:id], db_data[:definition], db_data[:iduser], db_data[:idkeyword], db_data[:pinned], db_data[:created].to_i, db_data[:changed].to_i]
      end
      db_data = DB[:definitions].where(id: db_definition[:id]).first
      action.push [:definitions, db_data[:id], db_data[:definition], db_data[:iduser], db_data[:idkeyword], db_data[:pinned], db_data[:created].to_i, db_data[:changed].to_i]
      DB[:actions].insert(
        iduser: user[:id],
        action: "update",
        payload: YAML::dump(action),
        created: Time.now.to_i,
      )

      # bereits gepinnten ueberschreiben
      if db_pinned_definition.any?
        DB[:definitions].where(id: db_pinned_definition[:id]).update(pinned: false)
      end

      # neuen speichern
      DB[:definitions].where(id: db_definition[:id]).update(pinned: true)
    end

    event.respond "Erledigt."

    # unbekannte option
  else
    event.respond "Unbekannte Option."
  end
end

# Fragt die Begriffs-DB ab.
# Jeder.
#
# Begriff
# Sucht Definitionen zum Begriff.
#
# --alles/--verbose
# Zeigt zusaetzlich Ersteller und Datum fuer Begriff, Alias und Definition an.
#
# --bsuche/--ksearch Begriff mit %-Wildcards
# Fuehrt eine Like-Suche nach Begriffen durch.
# Der Suchstring kann mit %-Wildcards gebaut werden, z. B. %string, string%, %string%.
# Standard ist %string%.
#
# #Hashtag
# Durchsucht Definitionen nach Hashtag und gibt deren Begriffe aus.
#
bot.command([:wasist, :whatis], description: "Fragt die Begriffs-Datenbank ab.", usage: '~wasist ( [ --alles ] ( Begriff | Doppel-Begriff | "Ein erweiterter Begriff" ) | --bsuche Suchtext-mit-%-Wildcards | #Hashtag )') do |event, *args|
  # channel pruefen
  return unless listening_here(event)

  seen(event)

  cmd = args.shift if args[0] =~ /^--/

  # tokenize nicht noetig bei abfragen (und macht die benutzung komplizierter)
  keyword = args.join(" ") || ""
  keyword.delete! "\""
  if keyword.empty?
    event.respond "Fehlerhafter Aufruf."
    return
  end
  if keyword =~ /^#/ and keyword =~ /\s/
    event.respond "Kein Hashtag."
    return
  end

  if keyword =~ /^#/
    keyword_set = DB[:keywords].select(:name, :definition).join(:definitions, :idkeyword => :id).where(Sequel.ilike(Sequel[:definitions][:definition], "%#{keyword}%")).where(hidden: false).order(:name)

    seen_keywords = []
    keyword_set.each do |row|
      # treffer mit hashtags einengen, weil like-suche zu viel findet
      if row[:definition] =~ /#{keyword}\b/i

        # doppelte keywords aussortieren
        if seen_keywords.include? row[:name]
          next
        else
          seen_keywords.push row[:name]
        end
      end
    end

    if seen_keywords.any?
      # ausgeben
      formatter(seen_keywords).each { |line| event.respond line }
    else
      event.respond "Unbekannt."
    end
  elsif cmd.nil? or cmd == "--alles" or cmd == "--verbose"
    # begriff bekannt?
    if cmd.nil?
      db_keyword = DB[:keywords].where({ Sequel.function(:upper, :name) => keyword.upcase }).first
      db_keyword = DB[:keywords].where({ Sequel.function(:upper, :name) => Sequel.function(:upper, keyword) }).first unless db_keyword
    else
      db_keyword = DB.fetch('SELECT `keywords`.*, `users`.`name` AS \'username\' FROM `keywords` INNER JOIN `users` ON (`users`.`id` = `keywords`.`iduser`) WHERE (UPPER(`keywords`.`name`) = ?)', keyword.upcase).first
    end
    unless db_keyword
      event.respond "Unbekannt."
      return
    end

    # alias aufloesen
    if db_keyword[:alias_id]
      if cmd.nil?
        db_orig_keyword = DB[:keywords].where(id: db_keyword[:alias_id]).first
        definition_set = DB[:definitions].where(idkeyword: db_keyword[:alias_id]).reverse_order(:pinned).order_append(:created)
      else
        db_orig_keyword = DB.fetch('SELECT `keywords`.*, `users`.`name` AS \'username\' FROM `keywords` INNER JOIN `users` ON (`users`.`id` = `keywords`.`iduser`) WHERE (`keywords`.`id` = ?)', db_keyword[:alias_id]).first
        definition_set = DB.fetch('SELECT `definitions`.*, `users`.`name` AS \'username\' FROM `definitions` INNER JOIN `users` on (`users`.`id` = `definitions`.`iduser`) WHERE (`definitions`.`idkeyword` = ?) ORDER BY `definitions`.`pinned` DESC, `definitions`.`created` ASC', db_keyword[:alias_id])
      end
    else
      if cmd.nil?
        definition_set = DB[:definitions].where(idkeyword: db_keyword[:id]).reverse_order(:pinned).order_append(:created)
      else
        definition_set = DB.fetch('SELECT `definitions`.*, `users`.`name` AS \'username\' FROM `definitions` INNER JOIN `users` on (`users`.`id` = `definitions`.`iduser`) WHERE (`definitions`.`idkeyword` = ?) ORDER BY `definitions`.`pinned` DESC, `definitions`.`created` ASC', db_keyword[:id])
      end
    end

    # bei alias auch original zeigen
    if db_orig_keyword
      if cmd.nil?
        event << "**#{db_keyword[:name]} (#{db_orig_keyword[:name]}):**"
      else
        created = Time.at(db_orig_keyword[:created].to_i)
        event << "**#{db_keyword[:name]} (#{db_orig_keyword[:name]})** #{db_orig_keyword[:username]} #{created.strftime("%H:%M %d.%m.%y")}:"
      end
    else
      if cmd.nil?
        event << "**#{db_keyword[:name]}:**"
      else
        created = Time.at(db_keyword[:created].to_i)
        event << "**#{db_keyword[:name]}** #{db_keyword[:username]} #{created.strftime("%H:%M %d.%m.%y")}:"
      end
    end

    # --primer zeigen
    if cmd and db_keyword[:primer]
      event << "Begriff ist Primer."
    end

    # aliase fuer --alles holen
    alias_set = DB.fetch('SELECT `keywords`.*, `users`.`name` AS \'username\' FROM `keywords` INNER JOIN `users` ON (`users`.`id` = `keywords`.`iduser`) WHERE (`keywords`.`alias_id` = ?)', db_keyword[:alias_id] ? db_keyword[:alias_id] : db_keyword[:id]).map { |row| "#{row[:name]} (#{row[:username]} #{Time.at(row[:created].to_i).strftime("%H:%M %d.%m.%y")})" }
    if cmd and alias_set.any?
      event << "Alias(e):"
      formatter(alias_set).each { |line| event << line }
      event << "Erläuterung(en):"
    end

    # hinweis
    # fuer mehrere templates pro keyword vorbereitet, dies wird aber nicht benutzt
    template_set = DB[:templates].where(idkeyword: (db_keyword[:alias_id] || db_keyword[:id]))
    template_set.each do |template|
      object = YAML::load template[:object]
      event << object.formatter
    end

    i = 0
    if cmd.nil?
      definition_set.each do |definition|
        event << "#{definition[:definition]} (#{i += 1})"
      end
    else
      definition_set.each do |definition|
        created = Time.at(definition[:created].to_i)
        pinned = "(gepinnt) " if definition[:pinned]
        event << "#{definition[:definition]} #{pinned}(#{definition[:username]} #{created.strftime("%H:%M %d.%m.%y")}) (#{i += 1})"
      end
    end
  elsif cmd == "--bsuche" or cmd == "--ksearch"
    if keyword.length < 3
      event.respond "Suchbegriff zu kurz. Drei Zeichen bitte."
      return
    elsif keyword !~ /%/
      keyword = "%" + keyword + "%"
    end

    # begriff bekannt?
    db_keywords = DB[:keywords].where(Sequel.ilike(:name, keyword)).where(hidden: false).order(:name)
    unless db_keywords.any?
      event.respond "Unbekannt."
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
    formatter(kw_names).each { |line| event.respond line }

    # unbekannte option
  else
    event.respond "Unbekannte Option."
  end

  return
end

# Loescht aus der Begriffs-Datenbank.
# Nur Bot-User.
#
# Begriff Ziffer
# Löscht Erklaerung unter Angabe der Ziffer aus wasist.
#
# --alias Begriff
# Löscht Alias.
#
# --pin Begriff
# Setz gepinnten Eintrag des Begriffs zurueck.
#
bot.command([:vergiss, :undefine], description: "Löscht aus der Begriffs-Datenbank.", usage: '~vergiss ( ( Begriff | Doppel-Begriff | "Ein erweiterter Begriff" ) Klammer-Ziffer aus ~wasist | ( --alias | --pin ) ( Begriff | Doppel-Begriff | "Ein erweiterter Begriff" ) )') do |event, *args|
  # channel pruefen
  return unless listening_here(event)

  # recht zum aufruf pruefen
  user = DB[:users].where(discord_id: event.user.id, enabled: true).first
  unless user
    event.respond "Nur Bot-User dürfen das!"
    return
  end

  seen(event, user)

  cmd = args.shift if args[0] =~ /^--/

  targs = tokenize(args)

  keyword = targs.shift || ""
  keyword.delete! "\""
  if keyword.empty?
    event.respond "Fehlerhafter Aufruf."
    return
  end

  if cmd.nil?
    # begriff bekannt?
    db_keyword = DB[:keywords].where({ Sequel.function(:upper, :name) => Sequel.function(:upper, keyword) }).first
    unless db_keyword
      event.respond "Unbekannt."
      return
    end

    # alias aufloesen
    if db_keyword[:alias_id]
      definition_set = DB[:definitions].where(idkeyword: db_keyword[:alias_id])
    else
      definition_set = DB[:definitions].where(idkeyword: db_keyword[:id])
    end

    # bezeichner des zu loeschenden eintrags vorhanden?
    if targs[0] !~ /^\d+$/
      # nur noetig, wenn mehr als ein eintrag vorhanden ist
      if definition_set.count > 1
        event.respond "Ziffer fehlt."
        return
      else
        targs[0] = 1
      end
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
      event.respond "Unbekannte Ziffer."
      return
    end

    # zur abfrage darstellen, eventuell verkuerzt
    token = db_definition[:definition].split(/ /)
    db_definition[:definition] = token[0] + " .. " + token[-1] if token.size > 3
    event.respond "Eintrag \"#{db_definition[:definition]}\" wirklich löschen? (j/n)"

    # sicherheitsabfrage
    event.user.await(:wirklich) do |wirklich_event|
      if wirklich_event.message.content.downcase == "j"

        # nur ein eintrag und keine templates: keyword, aliase und eintrag loeschen
        if definition_set.count == 1 and !db_template
          DB.transaction do
            # fuer undo merken
            db_data_set = DB[:keywords].where(id: db_definition[:idkeyword]).or(alias_id: db_definition[:idkeyword])
            action = []
            db_data_set.each do |row|
              action.push [:keywords, row[:id], row[:name], row[:iduser], row[:alias_id], row[:primer], row[:hidden], row[:created].to_i, row[:changed].to_i]
            end
            definition_set.each do |row|
              action.push [:definitions, row[:id], row[:definition], row[:iduser], row[:idkeyword], row[:pinned], row[:created].to_i, row[:changed].to_i]
            end
            DB[:actions].insert(
              iduser: user[:id],
              action: "delete",
              payload: YAML::dump(action),
              created: Time.now.to_i,
            )

            DB[:keywords].where(id: db_definition[:idkeyword]).or(alias_id: db_definition[:idkeyword]).delete
            definition_set.delete
          end

          # mehrere eintraege: einen loeschen
        else
          DB.transaction do
            # fuer undo merken
            db_data = DB[:definitions].where(id: db_definition[:id]).first
            action = [
              [:definitions, db_data[:id], db_data[:definition], db_data[:iduser], db_data[:idkeyword], db_data[:pinned], db_data[:created].to_i, db_data[:changed].to_i],
            ]
            DB[:actions].insert(
              iduser: user[:id],
              action: "delete",
              payload: YAML::dump(action),
              created: Time.now.to_i,
            )

            definition_set.where(id: db_definition[:id]).delete
          end
        end

        wirklich_event.respond "Erledigt."
      else
        wirklich_event.respond "Dann nicht."
      end
    end

    return
  elsif cmd == "--alias"
    # begriff bekannt?
    db_keyword = DB[:keywords].where({ Sequel.function(:upper, :name) => Sequel.function(:upper, keyword) }).first
    unless db_keyword
      event.respond "Unbekannt."
      return
    end

    # begriff muss alias sein
    unless db_keyword[:alias_id]
      event.respond "Kein Alias."
      return
    end

    DB.transaction do
      # fuer undo merken
      db_data = DB[:keywords].where(id: db_keyword[:id]).first
      action = [
        [:keywords, db_data[:id], db_data[:name], db_data[:iduser], db_data[:alias_id], db_data[:primer], db_data[:hidden], db_data[:created].to_i, db_data[:changed].to_i],
      ]
      DB[:actions].insert(
        iduser: user[:id],
        action: "delete",
        payload: YAML::dump(action),
        created: Time.now.to_i,
      )

      DB[:keywords].where(id: db_keyword[:id]).delete
    end

    event.respond "Erledigt."
  elsif cmd == "--pin"
    # begriff bekannt?
    db_keyword = DB[:keywords].where({ Sequel.function(:upper, :name) => Sequel.function(:upper, keyword) }).first
    unless db_keyword
      event.respond "Unbekannt."
      return
    end

    # alias aufloesen
    if db_keyword[:alias_id]
      db_definition = DB[:definitions].where(idkeyword: db_keyword[:alias_id], pinned: true).first
    else
      db_definition = DB[:definitions].where(idkeyword: db_keyword[:id], pinned: true).first
    end

    unless db_definition
      event.respond "Kein Eintrag gepinnt."
      return
    end

    DB.transaction do
      # fuer undo merken
      db_data = DB[:definitions].where(id: db_definition[:id]).first
      action = [
        [:definitions, db_definition[:id], db_definition[:definition], db_definition[:iduser], db_definition[:idkeyword], db_definition[:pinned], db_definition[:created].to_i, db_definition[:changed].to_i],
      ]
      DB[:actions].insert(
        iduser: user[:id],
        action: "update",
        payload: YAML::dump(action),
        created: Time.now.to_i,
      )

      DB[:definitions].where(id: db_definition[:id]).update(pinned: false)
    end

    event.respond "Erledigt."

    # unbekannte option
  else
    event.respond "Unbekannte Option."
  end
end

# Bot-Info
# Jeder.
#
bot.command([:ueber, :about], description: "Nennt Bot-Infos.") do |event, *args|
  # channel pruefen
  return unless listening_here(event)

  seen(event)

  event << "v#{get_version} #{get_website}"
  event << "#{DB[:users].count} Benutzer (#{DB[:users].where(enabled: true).count} aktiv/#{DB[:users].where(enabled: false).count} inaktiv)"
  event << "#{DB[:keywords].where(alias_id: nil, hidden: false).count} Begriffe und #{DB[:keywords].where(hidden: false).exclude(alias_id: nil).count} Aliase"
  event << "#{DB[:definitions].join(:keywords, :id => :idkeyword).where(hidden: false).count} Erklärungen"
end

# Benutzerverwaltung
# Nur fuer Bot-Master.
#
# --add Discord-User [Botmaster]
# Fuegt Benutzer zum Bot hinzu.
# "Botmaster" legt Benutzer als Bot-Master an.
#
# --enable Discord-User
# Aktiviert Benutzer.
# Nur aktive Benutzer koennen schreibend auf die Begriffs-DB zugreifen.
# Standard nach Anlegen.
#
# --disable Discord-User
# Setzt Benutzer inaktiv.
# Kann nicht auf Bot-Master angewandt werden.
#
# --botmaster Discord-User
# Macht Benutzer zum Bot-Master.
#
# --list
# Listet Bot-Benutzer auf.
#
bot.command([:benutzer, :user], description: "Regelt Benutzer-Rechte. Nur Bot-Master.", usage: "~benutzer --list | --add  Discord-User [Botmaster] | ( --enable | --disable  | --botmaster Discord-User )") do |event, *args|
  # channel pruefen
  return unless listening_here(event)

  # sonderregel fuer ersten benutzer
  if DB[:users].first
    # sonst recht zum aufruf pruefen
    user = DB[:users].where(discord_id: event.user.id, botmaster: true, enabled: true).first
    unless user
      event.respond "Nur Bot-Master dürfen das!"
      return
    end

    seen(event, user)
  else
    no_users = true
  end

  cmd = args.shift

  targs = tokenize(args)

  # add
  if cmd == "--add"
    duser = targs.shift || ""
    duser.delete! "\""
    if duser.empty?
      event.respond "Fehlerhafter Aufruf."
      return
    end

    # gibt es den discord-user?
    new_user = {}
    bot.users.each do |u|
      if u[1].username.downcase == duser.downcase
        new_user["username"] = u[1].username
        new_user["id"] = u[1].id
        break
      end
    end
    if new_user.empty?
      event.respond "Unbekannter Discord-User."
      return
    end

    # gibt es den user schon im bot?
    old_user = DB[:users].where(discord_id: new_user["id"]).first
    if old_user
      event.respond "User schon vorhanden."
      return
    end

    # der erste benutzer bei "no_users" ist immer botmaster
    if args[1]&.downcase == "botmaster" or no_users
      new_user["botmaster"] = 1
    else
      new_user["botmaster"] = 0
    end

    now = Time.now.to_i
    DB[:users].insert(
      discord_id: new_user["id"],
      name: new_user["username"],
      botmaster: new_user["botmaster"],
      enabled: 1,
      created: now,
      changed: now,
    )

    event.respond "Erledigt."

    # disable
  elsif cmd =~ /^--(enable|disable)$/
    duser = targs.shift || ""
    duser.delete! "\""
    if duser.empty?
      event.respond "Fehlerhafter Aufruf."
      return
    end

    # gibt es den user im bot?
    target_user = DB[:users].where({ Sequel.function(:upper, :name) => Sequel.function(:upper, duser) }).first
    unless target_user
      event.respond "Nicht vorhanden."
      return
    end

    # user darf kein botmaster sein
    if target_user[:botmaster]
      event.respond "User darf kein Bot-Master sein."
      return
    end

    if cmd == "--enable"
      enabled = true
    else
      enabled = false
    end

    DB[:users].where(id: target_user[:id]).update(enabled: enabled)

    event.respond "Erledigt."

    # botmaster
  elsif cmd == "--botmaster"
    duser = targs.shift || ""
    duser.delete! "\""
    if duser.empty?
      event.respond "Fehlerhafter Aufruf."
      return
    end

    # gibt es den user im bot?
    target_user = DB[:users].where({ Sequel.function(:upper, :name) => Sequel.function(:upper, duser) }).first
    unless target_user
      event.respond "User nicht vorhanden."
      return
    end

    DB[:users].where(id: target_user[:id]).update(botmaster: true)

    event.respond "Erledigt."

    # list
  elsif cmd == "--list"
    en_users = DB[:users].where(enabled: true).order(:name)
    dis_users = DB[:users].where(enabled: false).order(:name)

    unless en_users.empty?
      event << "__User:__"
      en_users.each do |user|
        botmaster = user[:botmaster] ? ", Botmaster" : ""
        event << user[:name] + botmaster
      end
    end

    unless dis_users.empty?
      event << "__Inaktive:__"
      dis_users.each do |user|
        botmaster = user[:botmaster] ? ", Botmaster" : ""
        event << user[:name] + botmaster
      end
    end

    if en_users.empty? and dis_users.empty?
      event << "Keine User."
    end

    # unbekannte option
  else
    event.respond "Unbekannte Option."
  end
end

# Zeigt Begriffe mit neuen Erklaerungen.
# Jeder.
#
bot.command([:neueste, :latest], description: "Zeigt die neuesten Einträge der Begriffs-Datenbank.", usage: "~neueste") do |event, *args|
  # channel pruefen
  return unless listening_here(event)

  seen(event)

  definition_set = DB[:keywords].select(:name, Sequel[:definitions][:created]).join(:definitions, :idkeyword => :id).where(hidden: false).reverse_order(Sequel[:definitions][:created]).limit(get_show_latest + 50)
  template_set = DB[:keywords].select(:name, Sequel[:templates][:created]).join(:templates, :idkeyword => :id).where(hidden: false).reverse_order(Sequel[:templates][:created]).limit(get_show_latest + 50)
  dataset = definition_set.all + template_set.all
  sdataset = dataset.sort_by { |row| row[:created] }.reverse

  event << "**Die neuesten Einträge:**"

  unless sdataset.count > 0
    event << "Keine."
    event << "Das ist ein bisschen traurig."
    return
  end

  # doppelte keywords aussortieren
  seen_keywords = []
  sdataset.each do |entry|
    break if seen_keywords.size == get_show_latest
    if seen_keywords.include? entry[:name]
      next
    else
      seen_keywords.push entry[:name]
    end
  end

  # ausgeben
  #formatter(seen_keywords).each {|line| event.respond line }
  formatter(seen_keywords).each { |line| event << line }

  return
end

# Wuerfelt mit verschiedenen Wuerfeln.
# Jeder.
#
# Anzahl der Wuerfe mal Seitenzahl.
# Standard ist 1d6.
#
bot.command([:wuerfeln, :roll], description: "Würfelt bis 9d999.", usage: "~wuerfeln [ 1 - 9 ( d | w ) 1 - 999 ]") do |event, *args|
  # channel pruefen
  return unless listening_here(event)

  seen(event)

  args.push "1d6" unless args.any?
  unless args[0] =~ /^([1-9])(?:(?:d|w)([1-9]\d{,2}))?$/
    event.respond "Fehlerhafter Aufruf."
    return
  end
  anzahl = $1.to_i
  seiten = $2 || 6

  erg = []
  rng = Random.new
  (1..anzahl).each do |i|
    erg.push "." * (rand(6) + 1)
    erg.push rng.rand(seiten.to_i) + 1
  end

  event.respond ":game_die:" + erg * " "

  return
end

# Fragt die Datenbank mit einem zufaelligen Begriff ab.
# Jeder.
#
bot.command([:zufaellig, :random, :rnd], description: "Zeigt einen zufälligen Begriff.", usage: "~zufaellig") do |event, *args|
  # channel pruefen
  return unless listening_here(event)

  seen(event)

  db_keyword = DB[:keywords].where(hidden: false).order(Sequel.lit("RANDOM()")).first
  unless db_keyword
    event << "Es gibt keine Einträge."
    event << "Das ist ein bisschen traurig."
    return
  end

  bot.execute_command(:wasist, event, [db_keyword[:name]])
end

# Datenbank-Verwaltung
# Nur Bot-Master.
#
# --export
# Stellt die Datenbank zeitlich begrenzt zum Download bereit.
#
bot.command([:datenbank, :database, :db], description: "Datenbank-Verwaltung. Nur Bot-Master.", usage: "~datenbank --export") do |event, *args|
  # channel pruefen
  return unless listening_here(event)

  # recht zum aufruf pruefen
  user = DB[:users].where(discord_id: event.user.id, botmaster: true, enabled: true).first
  unless user
    event.respond "Nur Bot-Master dürfen das!"
    return
  end

  seen(event, user)

  cmd = args.shift

  targs = tokenize(args)

  if cmd == "--export"
    uri = URI("http://#{get_dl_hostname}:#{get_dl_host_port}")
    begin
      res = Net::HTTP.get_response(uri)
    rescue
    else
      event.respond "Das geht gerade nicht. Bitte warte 60 Sekunden."
      return
    end

    # datei bereitstellen
    filename = "bot-" + SecureRandom.urlsafe_base64(10) + ".db"
    FileUtils.cp "db/bot.db", "public/#{filename}"
    zfilename = filename + ".gz"
    Zlib::GzipWriter.open("public/#{zfilename}") do |gz|
      gz.write IO.binread("public/#{filename}")
    end
    FileUtils.rm "public/#{filename}"

    # webserver
    server = Adsf::Server.new(host: "0.0.0.0", root: "public")

    event.respond "SQLite-Datenbank für 60 s verfügbar http://#{get_dl_hostname}:#{get_dl_host_port}/#{zfilename}"

    # timer
    scheduler = Rufus::Scheduler.new
    scheduler.in "60s" do
      server.stop
      FileUtils.rm "public/#{zfilename}"
    end

    server.run
    scheduler.join

    # unbekannte option
  else
    event.respond "Unbekannte Option."
  end
end

# Zeigt alle Hashtags.
# Jeder.
#
bot.command([:tagszeigen, :showtags], description: "Zeigt alle Hashtags.", usage: "~tagszeigen") do |event, *args|
  # channel pruefen
  return unless listening_here(event)

  seen(event)

  definition_set = DB[:definitions].where(Sequel.ilike(:definition, "%#%")).map(:definition)

  event << "**Alle Hashtags:**"

  unless definition_set.any?
    event << "Keine."
    event << "Das ist ein bisschen traurig."
    return
  end

  seen_tags = []
  definition_set.each do |definition|
    definition.scan(/(?:^|\s+)(#[[:alnum:]]+)/).flatten.each do |d|
      d.downcase!
      if seen_tags.include? d
        next
      else
        seen_tags.push(d) if d =~ /#[[:alnum:]]+/
      end
    end
  end

  # ausgeben
  formatter(seen_tags.sort).each { |line| event << line }

  return
end

# Macht bestimmte Aktionen waehrend einer begrenzten Zeitspanne rueckgaengig
# Nur Bot-User.
#
bot.command([:aufheben, :undo], description: "Kann Sachen rückgängig machen. Funktioniert für #{get_undo_timeout} s nach der Aktion.", usage: "~undo") do |event, *args|
  # channel pruefen
  return unless listening_here(event)

  # recht zum aufruf pruefen
  user = DB[:users].where(discord_id: event.user.id, enabled: true).first
  unless user
    event.respond "Nur Bot-User dürfen das!"
    return
  end

  #unless user[:id] == 1
  #event.respond 'Das geht noch nicht.'
  #return
  #end

  seen(event, user)

  # gibt es etwas rueckgaengig zu machen?
  db_action = DB[:actions].where(iduser: user[:id], applied: false).reverse_order(:created).first
  unless db_action
    event.respond "Keine Aktion aufzuheben."
    return
  end

  # zeit ueberschritten
  now = Time.now.to_i
  unless now - db_action[:created].to_i < get_undo_timeout
    event.respond "Das geht nicht mehr."
    return
  end

  if db_action[:action] == "insert"
    DB.transaction do
      payload = YAML::load db_action[:payload]
      # gibt es die daten noch?
      db_data = DB[payload[0][0]].where(id: payload[0][1]).first
      unless db_data
        event.respond "Das geht nicht mehr."
        return
      end

      # immer pruefen, ob datensatz noch da
      # plus
      # pruefen abhaengig von der payload
      #
      # keyword + definition/template
      # alias dazu - alias_id und datum in keywords
      # definition dazu - idkeyword und datum in definitions
      # template dazu/geaendert - idkeyword und datum in templates
      #
      # definition
      # weg - action delete und datum + tabelle und idkeyword gleich
      #
      db_added_alias, db_added_def, db_changed_tpl, removed_def = false, false, false, false
      if payload.size > 1
        db_added_alias = DB[:keywords].where(Sequel[:created] > db_action[:created].to_i).or(Sequel[:changed] > db_action[:created].to_i).where(alias_id: payload[0][1]).first
        db_added_def = DB[:definitions].where(Sequel[:created] > payload[0][-2].to_i).or(Sequel[:changed] > payload[0][-1].to_i).where(idkeyword: payload[0][1]).first
        db_changed_tpl = DB[:templates].where(Sequel[:created] > payload[0][-2].to_i).or(Sequel[:changed] > payload[0][-1].to_i).where(idkeyword: payload[0][1]).first
      else
        # todo
        # hier pruefen, ob es nur noch eine defintion gibt
        db_removed_def_set = DB[:actions].where(Sequel[:created] > db_action[:created].to_i).where(action: "delete").exclude(iduser: user[:id])
        db_removed_def_set.each do |row|
          removed_payload = YAML::load row[:payload]
          if removed_payload[0][0] == :definitions and removed_payload[0][4] == payload[0][4]
            removed_def = true
            break
          end
        end
      end
      if db_added_alias or db_added_def or db_changed_tpl or removed_def
        event.respond "Das geht nicht mehr."
        return
      end

      payload.each do |pl|
        DB[pl[0]].where(id: pl[1]).delete
      end
    end
  elsif db_action[:action] == "update"
    DB.transaction do
      payload = YAML::load db_action[:payload]
      if payload[0][0] == :keywords
        db_data = DB[:keywords].where(id: payload[0][1]).first
        unless db_data
          event.respond "Das geht nicht mehr."
          return
        end

        # payload pruefen
        # keyword geaendert - id und datum in keywords
        db_changed_kw = DB[:keywords].where(Sequel[:created] > db_action[:created].to_i).or(Sequel[:changed] > db_action[:created].to_i).where(id: payload[0][1]).first
        if db_changed_kw
          event.respond "Das geht nicht mehr."
          return
        end

        payload[0][6] = false unless payload[0][6]
        DB[:keywords].where(id: payload[0][1]).update(primer: payload[0][5], hidden: payload[0][6], changed: now)
        db_data = DB[:keywords].where(id: payload[0][1]).first

        # gibt es die daten noch?
        # unflexibel, weil dies wegen 'idkeyword' nur fuer updates von 'templates' funktioniert
        # alternativ pruefen, ob es in 'actions' einen delete-eintrag fuer dieses idkeyword gibt.
      elsif payload[0][0] == :templates
        db_data = DB[payload[0][0]].where(idkeyword: payload[0][1]).first
        unless db_data
          event.respond "Das geht nicht mehr."
          return
        end

        # payload pruefen
        # template geaendert - idkeyword und datum in templates
        db_changed_tpl = DB[:templates].where(Sequel[:created] > db_action[:created].to_i).or(Sequel[:changed] > db_action[:created].to_i).where(idkeyword: payload[0][1]).first
        if db_changed_tpl
          event.respond "Das geht nicht mehr."
          return
        end

        DB[payload[0][0]].where(idkeyword: payload[0][1]).update(object: payload[0][2], changed: now)

        # payload pruefen
        # gibt es das keyword noch?
        # gibt es die eintraege noch?
        # wurde sonst aenderungen an der definition vorgenommen, die in actions notiert sind?
      elsif payload[0][0] == :definitions
        payload.each do |pl|
          db_definition = DB[:definitions].where(id: pl[1]).first
          db_keyword = DB[:keywords].where(id: pl[4]).first
          db_changed_def = DB[:actions].where(Sequel[:created] > db_action[:created].to_i).where(action: "update").exclude(iduser: user[:id]).first
          changed_def = false
          if db_changed_def
            changed_payload = YAML::load db_changed_def[:payload]
            changed_payload.each do |cpl|
              if cpl[0] == :definitions and cpl[4] == pl[4]
                changed_def = true
                break
              end
            end
          end

          unless db_definition and db_keyword and !changed_def
            event.respond "Das geht nicht mehr."
            return
          end
        end

        payload.each do |pl|
          DB[:definitions].where(id: pl[1]).update(pinned: pl[5], created: pl[6], changed: pl[7])
        end
      end
    end
  elsif db_action[:action] == "delete"
    # keyword + definition
    # keyword dazu
    #
    # definition
    # keyword weg
    #
    # keyword + template
    # keyword dazu
    #
    # alias
    # eintrag mit gleichem namen vorhanden
    # ehemaliges ziel-keyword weg

    DB.transaction do
      payload = YAML::load db_action[:payload]

      #if payload.size > 1
      # payload pruefen
      # keyword darf inzwischen nicht als solches oder alias angelegt worden sein
      db_added_same_kw_or_alias = false
      payload.each do |pl|
        if pl[0] == :keywords and DB[:keywords].where(name: pl[2]).or(alias_id: pl[2]).first
          added_same_kw_or_alias = true
          break
        end
      end
      #else
      # payload pruefen
      # keyword muss noch da sein
      db_keyword = DB[:keywords].where(id: payload[0][4]).first
      #end

      if db_added_same_kw_or_alias or !db_keyword
        event.respond "Das geht nicht mehr."
        return
      end

      DB[payload[0][0]].insert(
        id: payload[0][1],
        name: payload[0][2],
        iduser: payload[0][3],
        alias_id: payload[0][4],
        primer: payload[0][5],
        hidden: payload[0][6],
        created: payload[0][7],
        changed: payload[0][8],
      )
    end
  else
  end

  DB[:actions].where(id: db_action[:id]).update(applied: true)

  event.respond "Erledigt."
end

# Schreibt in das private Log des Benutzers
# Nur Bot-User.
#
# Eintrag
# Speichert Eintrag
#
# --latest [1-99] (Standard 5)
# Zeigt die letzten Eintraege an.
#
# --at TT.MM.[JJ]
# Zeigt die Eintraege dieses Datums.
# Wird das Jahr weggelassen, so wird das aktuelle angenommen.
#
# --show-tags
# Zeigt alle Hashtags.
#
bot.command([:log], description: "Privates Tagebuch (nicht wirklich privat)", usage: "~log ( Macht einen Eintrag | [--latest [1-99] ] | [--at TT.MM.[YY] ] | --show-tags )") do |event, *args|
  # channel pruefen
  return unless listening_here(event)

  # recht zum aufruf pruefen
  user = DB[:users].where(discord_id: event.user.id, enabled: true).first
  unless user
    event.respond "Nur Bot-User dürfen das!"
    return
  end

  seen(event, user)

  cmd = args.shift if args[0] =~ /^--/

  targs = tokenize(args)

  # eintrag speichern
  if cmd.nil?
    if targs.empty?
      event.respond "Fehlerhafter Aufruf."
      return
    end

    # eintrag speichern
    now = Time.now.to_i
    DB.transaction do
      DB[:diaries].insert(
        iduser: user[:id],
        entry: targs.join(" "),
        created: now,
        changed: now,
      )
    end

    event.respond "Erledigt."

    # --latest
  elsif cmd == "--latest"
    if targs.size > 0 and targs[0] !~ /^[1-9]\d?$/i
      event.respond "Fehlerhafter Aufruf."
      return
    end

    anzahl = targs.shift
    anzahl = 5 unless anzahl

    diary_set = DB[:diaries].where(iduser: user[:id]).reverse_order(:created).limit(anzahl)
    diary_set.each do |row|
      created = Time.at(row[:created].to_i)
      event << "#{row[:entry]} (#{created.strftime("%d.%m.%y %H:%M")})"
    end

    if diary_set.empty?
      event << "Es gibt keine Einträge."
      event << "Das ist ein bisschen traurig."
    end

    return

    # --at
  elsif cmd == "--at"
    if targs.empty?
      event.respond "Fehlerhafter Aufruf."
      return
    end
    # jahr anhaengen
    if targs[0] =~ /^\d\d?\.\d\d?\.$/
      targs[0].concat(Date.today.strftime("%y"))
    end
    # datum pruefen
    begin
      date = DateTime.strptime(targs[0], "%d.%m.%y")
    rescue ArgumentError => e
      event.respond "Fehlerhafter Aufruf."
      return
    end

    time = date.to_time
    mitternacht = time.to_i
    diary_set = DB[:diaries].where(iduser: user[:id], created: mitternacht..(mitternacht + 86399))
    diary_set.each do |row|
      created = Time.at(row[:created].to_i)
      event << "#{row[:entry]} (#{created.strftime("%H:%M")})"
    end

    if diary_set.empty?
      event << "Keine Einträge gefunden."
    end

    return

    # --show-tags
  elsif cmd == "--show-tags"
    diary_set = DB[:diaries].where(Sequel.ilike(:entry, "%#%")).map(:entry)

    unless diary_set.any?
      event << "Keine Hashtags gefunden."
      return
    else
      event << "**Alle Hashtags:**"
    end

    seen_tags = []
    diary_set.each do |entry|
      entry.scan(/(?:^|\s+)(#[[:alnum:]]+)/).flatten.each do |e|
        e.downcase!
        if seen_tags.include? e
          next
        else
          seen_tags.push(e) if e =~ /#[[:alnum:]]+/
        end
      end
    end

    # ausgeben
    formatter(seen_tags.sort).each { |line| event << line }

    return
    # unbekannte option
  else
    event.respond "Unbekannte Option."
  end
end

# Bot-Verwaltung
# Nur Bot-Master.
#
# --info
# Gibt verschiedene Informationen aus.
#
bot.command([:bot], description: "", usage: "") do |event, *args|
  # channel pruefen
  return unless listening_here(event)

  # recht zum aufruf pruefen
  user = DB[:users].where(discord_id: event.user.id, botmaster: true, enabled: true).first
  unless user
    event.respond "Nur Bot-Master dürfen das!"
    return
  end

  seen(event, user)

  cmd = args.shift

  targs = tokenize(args)

  if cmd == "--info"
    event << "Autor: " + event.author.name
    event << "Kanal: " + event.channel.name
    event << "Kanal-ID: " + event.channel.id.to_s
    event << "Hört hier zu: " + listening_here(event).to_s

    # unbekannte option
  else
    event.respond "Unbekannte Option."
  end
end

def shut_down(b)
  bot = b
  puts "Auf Wiedersehen!"
  bot.stop
end

Signal.trap("INT") {
  shut_down(bot)
  exit
}

bot.run
