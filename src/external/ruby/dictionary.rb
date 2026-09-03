module Tape
	class Dictionary < Instance
		extend Ruby_Proxies
		attr_accessor :hash

		def initialize hash = nil
			super 'Dictionary'
			@hash                 = hash || {}
			@declarations['hash'] = @hash
		end

		proxy_delegate 'hash'
		proxy :has_key?
		proxy :delete
		proxy :count
		proxy :empty?
		proxy :clear
		proxy :fetch

		def proxy_keys
			Tape::Array.new hash.keys
		end

		def proxy_values
			Tape::Array.new hash.values
		end

		def proxy_merge other_hash
			Tape::Dictionary.new hash.merge other_hash.hash
		end

		# note; To prevent Scope#[] or Scope#get from missing out on the actual location of the hash. Standard members still call through to [] and get. I'm manually calling these proxy methods in some places. @copypaste from array.rb
		def proxy_get key
			hash[key.to_sym]
		end

		def proxy_set key, value
			hash[key.to_sym] = value
		end

		def == other
			hash == other&.hash
		end

		def to_s
			hash.inspect
		end
	end
end
