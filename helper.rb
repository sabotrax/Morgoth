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
