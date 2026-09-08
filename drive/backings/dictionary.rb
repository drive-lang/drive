module Disk
	class Dictionary < Instance
		extend Ruby_Proxies
		attr_accessor :hash

		def initialize hash = nil
			super 'Dictionary'
			@hash                 = hash || {}
			@declarations['hash'] = @hash
		end

		proxy_delegate 'hash'
		proxy :count
		proxy :empty?
		proxy :clear

		def proxy_keys
			Disk::Array.new hash.keys
		end

		def proxy_values
			Disk::Array.new hash.values
		end

		def proxy_merge other_hash
			Disk::Dictionary.new hash.merge other_hash.hash
		end

		# A key argument reaching any of these five can be a raw Ruby String/Symbol (a literal interpreted directly, e.g. by #interp_infix_assignment's own subscript handling) or a real Disk::String instance (an ordinary call argument, e.g. a variable holding one) -- Disk::String has no #to_sym of its own, so unwrap it to its real Ruby value first either way.
		def normalize_dict_key key
			(key.is_a?(Disk::String) ? key.value : key).to_sym
		end

		# note; To prevent Scope#[] or Scope#get from missing out on the actual location of the hash. Standard members still call through to [] and get. I'm manually calling these proxy methods in some places. @copypaste from array.rb
		def proxy_get key
			hash[normalize_dict_key(key)]
		end

		def proxy_set key, value
			hash[normalize_dict_key(key)] = value
		end

		# `[]`/`[]=` (#proxy_get/#proxy_set above) normalize the key to a Symbol before touching `hash` -- these three need the exact same normalization, or a String key (`d.has_key?('color')`) silently never matches what's actually stored (`d['color'] = 1` really wrote `hash[:color]`), since a plain `proxy :has_key?`/`:delete`/`:fetch` would hand the raw argument straight to Ruby's own Hash methods with no such conversion.
		def proxy_has_key? key
			hash.has_key? normalize_dict_key(key)
		end

		def proxy_delete key
			hash.delete normalize_dict_key(key)
		end

		def proxy_fetch key, default = nil
			hash.fetch normalize_dict_key(key), default
		end

		def == other
			hash == other&.hash
		end

		def to_s
			hash.inspect
		end
	end
end
