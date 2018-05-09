#!/usr/bin/env ruby

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

# Zum Erweitern von in der Datenbank vorhandenen Schiffsobjekten
#
# Nach einer Erweiterung des Schiffsobjekt (z. B. um Utility Mounts) in der Klasse,
# muessen auch die schon in der DB vorhandenen Eintraege erweitert werden.
# Dazu dient dieses Tool.

require 'sequel'
require 'yaml'

require_relative 'ship'

DB = Sequel.connect('sqlite://db/bot.db')

ship = Ship.new
ship_attrs = ship.instance_variables

ships = []
DB[:templates].each do |template|
  db_ship = YAML::load template[:object]
  # objekte unterschiedlich?
  if db_ship.instance_variables.size != ship_attrs.size
    # dann kopieren
    new_ship = Ship.new
    new_ship.instance_variables.each do |attr|
      attr_literal = attr.to_s.tr('@', '')
      if db_ship.instance_variables.include? attr and db_ship.send("#{attr_literal}?") != 0
        begin
          new_ship.send("#{attr_literal}", db_ship.send("#{attr_literal}?"))
        rescue
          p db_ship.send("#{attr_literal}?")
          p $!
          exit 1
        end
      end
    end
    ships.push([template[:idkeyword], new_ship])
  end
end

puts "#{ships.size} Updates"
DB.transaction do
  ships.each do |ship|
    DB[:templates].where(idkeyword: ship[0].to_i).update(object: YAML::dump(ship[1]))
  end
end
