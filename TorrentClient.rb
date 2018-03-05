#!/usr/bin/ruby 
# Bittorrent Client
# A CMSC417 project at the University of Maryland
# If this blows your computer up. It's not my fault
# Written by Julian Moyse
require 'Torrent.rb'
require 'Tracker.rb'
	
if ARGV.length != 1
	puts "Invalid number of arguments"
	exit(1)
end

url = ARGV[0]
torrent = Torrent.new(url)

if torrent.torrentMetadata == nil
	puts "Bad torrent data.  Exiting ..."
	exit(1) 
end
puts "----------------------------------------------\n"
puts torrent
puts "----------------------------------------------\n"
tracker = Tracker.new(torrent)
puts tracker
puts "----------------------------------------------\n"
puts tracker.detailedPieceStatus
puts "----------------------------------------------\n"

server = Server.new(tracker)
peersList = tracker.peers

if peersList && peersList.length > 0
	peersList["peers"].each do |peer|
		peer_id = peer["peer id"]
		peer_port = peer["port"]
		peer_ip =  peer["ip"]
		found = false
		#puts "Peer: #{peer_ip}\t#{peer_port}"
		
		server.peers.each { |p|
			if p.ip == peer_ip && p.port == peer_port
				found = true
			end
		}
		if !peer_id.include?(tracker.peerID_base) && peer_id != tracker.peerID && peer_port != tracker.port && found == false  #don't add our own peerID
			#puts "New peer: #{peer_ip}\t#{peer_port}"
			server.addNewPeer(peer_ip, peer_port,peer_id)
		end
	end
end

server.startNewServer()

