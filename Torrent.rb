require 'BinaryDecoder.rb'
require 'digest/sha1'
require 'net/http'
require 'cgi'
require 'socket'
require 'Peer.rb'
require 'FilePiece.rb'
require 'Server.rb'
require 'ftools'
require 'io/nonblock'

class Torrent
	attr_accessor :torrentMetadata, :filename, :totalPieces, :pieces, :pieceLength, :fileSize, :sortedInfoMetadata, :encodedHash, :completeHash, :torrentFilename, :trackerURL,:announceList,:createdBy,:creationDate, :comment,:md5sum 

	def initialize(torrent)
		@torrentFilename = torrent
		torrentData = ""		
		begin
			timeout(10) do
				open(torrent) do |torrentURL|
					torrentURL.each do |line|
						torrentData+=line.to_s
					end
				end
			end
		rescue Exception => e
			puts debugMessage("Error openning torrent")
			return nil
		end
		
		if torrentData.length == 0
			puts debugMessage("Invalid torrent file data")
			exit(1)
		end

		decodeTorrent(torrentData)
	end

	def decodeTorrent(torrentData)
		# Creates binary encoded data from the torrent file
		torrentDecoder = BinaryDecoder.new
		torrentDecoder.BinaryDecoder(torrentData.to_s)

		torrentMetadata = torrentDecoder.getDecodedData()
		@filename = torrentMetadata["info"]["name"]
		@totalPieces = torrentMetadata["info"]["pieces"].length/20

		@pieces = String.new(torrentMetadata["info"]["pieces"])
		@pieceLength = torrentMetadata["info"]["piece length"]
		@fileSize = torrentMetadata["info"]["length"]
		@isPrivate = torrentMetadata["info"]["private"]
		@trackerURL = torrentMetadata["announce"]

		
		@announceList = torrentMetadata["announce-list"]
		@createdBy = torrentMetadata["comment"]
		@creationDate = torrentMetadata["creation date"]
		@comment = torrentMetadata["created by"]
		@md5sum = torrentMetadata["info"]["md5sum"]
		
		# has to be sorted first
		@sortedInfoMetadata = torrentMetadata["info"].keys.sort_by {|s| s.to_s}.map {|key| [key, torrentMetadata["info"][key]] }
		@torrentMetadata = torrentMetadata
		@encodedHash = getEncodedHash()
		@completeHash = CGI::unescape(@encodedHash)
	end
	
	def getEncodedHash()
		bEncodedHash = "d"
		@sortedInfoMetadata.each do |hashLine|
			if hashLine[1].is_a?(String)
				bEncodedHash+= hashLine[0].length.to_s+":"+hashLine[0].to_s+hashLine[1].length.to_s+":"+hashLine[1].to_s
			elsif hashLine[1].is_a?(Integer)
				bEncodedHash+=hashLine[0].length.to_s+":"+hashLine[0].to_s+"i"+hashLine[1].to_s+"e"
			end
		end
	
		bEncodedHash+="e"

		bEncodedHash = CGI::escape(Digest::SHA1.digest(bEncodedHash)).to_s # escape it so it can be sent via url	
		return bEncodedHash
	end

	def to_s()
		output = ""
		output += "Torrent Metadata:\n"
		output += "#{' Torrent URL'.ljust(25, ' ')} #{@torrentFilename}\n"
		output += "#{' Tracker(s)'.ljust(25, ' ')} #{@trackerURL}\n"
		output += "#{' Filename(s)'.ljust(25, ' ')} #{@filename}\n"
		
		#puts @completeHash.split("").to_i.pack("C")
		
		

		output += "#{' Info Hash'.ljust(25, ' ')} #{@completeHash.unpack('H*')}\n"
		
		output += "#{' Escaped Info Hash'.ljust(25, ' ')} #{@encodedHash}\n"
		output += "#{' File Size'.ljust(25, ' ')} #{@fileSize.to_s.gsub(/(\d)(?=\d{3}+(\.\d*)?$)/, '\1,')} bytes\n"
		output += "#{' Total Pieces'.ljust(25, ' ')} #{@totalPieces}\n"
		output += "#{' Piece Length'.ljust(25, ' ')} #{@pieceLength.to_s.gsub(/(\d)(?=\d{3}+(\.\d*)?$)/, '\1,')} bytes\n"
		

		if @isPrivate != nil && @isPrivate != ""
			output += "#{' Private'.ljust(25, ' ')} #{@isPrivate}\n"
		end
		
		if @md5sum != nil && @md5sum !=""
			output += "#{' Comment'.ljust(25, ' ')} #{@md5sum}\n"
		end
		
		if @announceList != nil && @announceList != ""
			output += "#{' Announce List'.ljust(25, ' ')} #{@announceList}\n"
		end
		
		if @createdBy != nil && @createdBy != ""
 			output += "#{' Created By'.ljust(25, ' ')} #{@createdBy}\n"
		end
		
		if @creationDate != nil && @creationDate != ""
			output += "#{' Creation Date'.ljust(25, ' ')} #{Time.at(@creationDate).strftime("%x")}\n"
		end
		
		if @comment != nil && @comment != ""
			output += "#{' Comment'.ljust(25, ' ')} #{@comment}\n"
		end
		
		return output;
	end

	def debugMessage(message)
		time = Time.now;
		return "[#{time.strftime("%X")}] #{message}"
	end

end
