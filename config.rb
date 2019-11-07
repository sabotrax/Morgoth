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

require "json"

module Config

  cfile = File.read("config.json")
  @@config = JSON.parse(cfile)

  def get_bot_client_id
    @@config["discord_client_id"]
  end

  def get_bot_token
    @@config["discord_bot_token"]
  end

  def get_bot_prefix
    @@config["prefix"]
  end

  def get_website
    @@config["website"]
  end

  def get_version
    @@config["version"]
  end

  def get_show_latest
    @@config["show_latest"]
  end

  def get_dl_hostname
    @@config["download_host"]
  end

  def get_dl_host_port
    @@config["download_port"]
  end

  def get_undo_timeout
    @@config["undo_timeout"]
  end

  def get_listening_channels
    @@config["listening_channels"]
  end

end
