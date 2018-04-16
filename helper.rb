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

# argumente in anfuehrungszeichen gruppieren
def tokenize(args)
  args.join(' ').scan(/(?:"[^"]+"|[^\s]+)/)
end

# in zeilen zu fuenf ausgeben
def formatter(tokens)
  formatted = []
  i = 0
  j = []
  tokens.each do |token|
    j.push token
    i += 1
    if i % 5 == 0
      formatted.push j.join(', ')
      j.clear
    elsif i == tokens.size
      formatted.push j.join(', ')
    end
  end
  return formatted
end

# Merkt sich Aufrufe
# Gibt bei Erstkontakt Hinweise und dynamische Keywords aus
#
def seen(event, user = nil)
  db_sighting = DB[:sightings].where(discord_user_id: event.user.id).first
  now = Time.now.to_i
  if db_sighting
    if user and ! db_sighting[:iduser]
      DB[:sightings].where(discord_user_id: event.user.id).update(iduser: user[:id], seen: now)
    else
      DB[:sightings].where(discord_user_id: event.user.id).update(seen: now)
    end
  else
    db_keywords = DB[:keywords].where(primer: true).select_map(:name)
    if db_keywords.size > 0
      event.user.pm 'Dies scheint dein erster Aufruf zu sein.'
      event.user.pm 'Vielleicht möchtest du dir diese Begriffe per **~wasist Begriff** anschauen:'
      formatter(db_keywords).each {|line| event.user.pm line }
    end

    if user
      DB[:sightings].insert(iduser: user[:id], discord_user_id: event.user.id, seen: now)
    else
      DB[:sightings].insert(discord_user_id: event.user.id, seen: now)
    end
  end
end
