require 'BinaryDecoder.rb'
require 'digest/sha1'
require 'net/http'
require 'cgi'
require 'socket'
require 'FilePiece.rb'
require 'ftools'

class Tracker
	attr_accessor :torrent, :piecesList, :peerID_base, :port, :peerID, :completed, :peers, :completePeers, :incompletePeers,:detailedPieceStatus
	
	def initialize(torrent)
		@peerID_base = "UM4171600-WTF"
		@port = 6882
		@filename = "downloaded" # Fallback filename, if theres an error reading the torrent metadata
		@maxPeers = 50
		@uploadRate = 0
		@downloadRate = 0

		@piecesList = Array.new
		@peerID="#{@peerID_base}-#{rand(9)}#{rand(9)}#{rand(9)}#{rand(9)}#{rand(9)}#{rand(9)}"

		@torrent = torrent
		@completed = generatePieces()
		@peers = getPeers()
	end

	def getPeers()
		bEncodedHash = @torrent.encodedHash
		amountLeft = @torrent.fileSize.to_i-@completeBytes.to_i
		
		trackerURL = @torrent.trackerURL+"?info_hash="+bEncodedHash+"&peer_id="+@peerID+"&port="+@port.to_s+"&uploaded=0&downloaded=0&left=#{amountLeft}&event=started"
		trackerResponse = connect(trackerURL)
		
		if trackerResponse == nil # can't connect correctly.  TODO: add in code to retry later
			return
		end		

		# Decoder the trackers reponse
		responseDecoder = BinaryDecoder.new
		responseDecoder.BinaryDecoder(trackerResponse)
		 
		@peers = responseDecoder.getDecodedData()
		@interval = peers["interval"]
		@incompletePeers = peers["incomplete"]
		@completePeers = peers["complete"]
		
		return @peers
	end
	
	
	def connect(url)
		begin
			timeout(5) do
				response = Net::HTTP.get URI.parse(url)
				return response
			end
		rescue Exception => e
			puts debugMessage("Error connecting to tracker")
			return nil
		end
	end
	
	
	def generatePieces()		@torrent.totalPieces.times{ |pieceNo|
			pieceHash = @torrent.pieces.slice!(0..19)
			file = FilePiece.new(pieceNo,pieceHash,@torrent.pieceLength,@torrent.fileSize,@torrent.filename)
			@piecesList.push(file)
		}
		# Run a SHA1 checksum on the torrent to determine which blocks of dat are good and which are bad
		@completeFiles = 0
		@completeBytes = 0
		@detailedPieceStatus = "Piece Statistics:\n"

		if File.exists?(@torrent.filename) && File.writable?(@torrent.filename) && !File.zero?(@torrent.filename) #&& File.size(@filename) == fileSize
			@completed = true
			@piecesList.each{|piece|
				if piece.checkHash() == false
					@detailedPieceStatus +=" Piece #{"%02d" % piece.segment_number} checksum fail.  Adding to queue\n"
					@completed = false
				else
					@completeFiles+=1
					@completeBytes+=piece.size
					piece.complete = true
				end		
			}
			if @completed
				@detailedPieceStatus +=" All SHA1 checksums valid\n"
				@detailedPieceStatus +=" Seeding started\n"
				return true
			else
				@detailedPieceStatus +=" SHA1 Checksum found #{@completeFiles}/#{@torrent.totalPieces} valid pieces\n"
				@detailedPieceStatus +=" Downloading started"
			end
		else
			@detailedPieceStatus +=" Failed to locate downloaded data. New file created\n"
			file = File.new(@torrent.filename, "w+b")
		end
		return false
	end

	def to_s()
		output = ""
		output += "Tracker Statistics:\n"
		output += "#{' Client Peer ID'.ljust(25, ' ')} #{@peerID}\n"
		output += "#{' Client Port'.ljust(25, ' ')} #{@port}\n"
		#output += "#{' Client IP'.ljust(25, ' ')} #{getExternalIP()}\n"
		output += "#{' Completed Pieces'.ljust(25, ' ')} #{@completeFiles}/#{@piecesList.length} (#{@completeFiles.to_f/@piecesList.length.to_f*100}%)\n"
		output += "#{' Completed Bytes'.ljust(25, ' ')} #{@completeBytes.to_s.gsub(/(\d)(?=\d{3}+(\.\d*)?$)/, '\1,')} bytes\n"
		output += "#{' Bytes Left'.ljust(25, ' ')} #{(@torrent.fileSize.to_i-@completeBytes.to_i).to_s.gsub(/(\d)(?=\d{3}+(\.\d*)?$)/, '\1,')} bytes\n"
		output += "#{' Seeding'.ljust(25, ' ')} #{completed ? 'Yes' : 'No'}\n"
		output += "#{' Total Peers'.ljust(25, ' ')} #{@incompletePeers+@completePeers}\n"
		output += "#{' Leechers'.ljust(25, ' ')} #{@incompletePeers}\n"
		output += "#{' Seeders'.ljust(25, ' ')} #{@completePeers}\n"
		return output
	end
	
	def getExternalIP()
		my_ip = (require 'open-uri' ; open("http://myip.dk") { |f| /([0-9]{1,3}\.){3}[0-9]{1,3}/.match(f.read)[0].to_a[0] })
		return my_ip
	end
	
	def debugMessage(message)
		time = Time.now;
		return "[#{time.strftime("%X")}] #{message}"
	end
end





