require 'open-uri'
require 'pp'

class BinaryDecoder
	public
	def BinaryDecoder(source)
		@source = source
	end
	
	def getDecodedData()
		return decode()
	end
	
	private 
	def decode()
		c = @source[0].chr
		case c
		when 'd'
			return parseDictionary()
		when '0'..'9'
			return parseString()
		when 'l'
			return parseList()
		when 'i'
			return parseInteger()
		end
	end
	
	def parseDictionary()
		dictionary = {}
		@source = @source.split(/d/,2)[1]
		while @source[0].chr!='e'
			key = parseString()
			value = decode()
			dictionary[key] = value
		end
		@source = @source.split(/e/,2)[1]
		return dictionary
	end
	
	def parseList()
		l = []
		@source = @source.split(/l/,2)[1]
		while @source[0].chr!='e'
			l.push(decode())
		end
		@source = @source.split(/e/,2)[1]
		return l
	end

	def parseInteger()
		arr = @source.split(/e/,2)
		
		@source = arr[1]
		number = arr[0].split(/i/,2)[1].to_i 
		
		return number
	end
	
	def parseString()
		arr = @source.split(/:/,2)
		bytes = arr[0]
		
		if (bytes == '0')
			extractedElement = arr[1][0..bytes.to_i-1]
			@source = extractedElement
			return ""					
		else
			extractedElement = arr[1][0..bytes.to_i-1]
			@source = arr[1][bytes.to_i..arr[1].length-1]
			return extractedElement
		end
	end	
end
