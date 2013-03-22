$LOAD_PATH.unshift '../../drivers/ruby/lib'
$LOAD_PATH.unshift '../../build/drivers/ruby/rdb_protocol'
require 'pp'
require 'rethinkdb'
extend RethinkDB::Shortcuts

JSPORT = ARGV[0]
CPPPORT = ARGV[1]

def show x
  if x.class == Err
    name = x.type.sub(/^RethinkDB::/, "")
    return "<#{name} #{'~ ' if x.regex}#{show x.message}>"
  end
  return (PP.pp x, "").chomp
end

NoError = "nope"
AnyUUID = "<any uuid>"
Err = Struct.new(:type, :message, :backtrace, :regex)
Bag = Struct.new(:items)

def bag list
  Bag.new(list)
end

def arrlen len, x
  Array.new len, x
end

def uuid
  AnyUUID
end

def err(type, message, backtrace)
  Err.new(type, message, backtrace, false)
end

def err_regex(type, message, backtrace)
  Err.new(type, message, backtrace, true)
end

def eq_test(one, two)
  return cmp_test(one, two) == 0
end

def cmp_test(one, two)

  if two.object_id == NoError.object_id
    return -1 if one.class == Err
    return 0
  end

  if two.object_id == AnyUUID.object_id
    return -1 if not one.kind_of? String
    return 0 if one.match /[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}/
    return 1
  end

  case "#{two.class}"
  when "Err"
    if one.kind_of? Exception
      one = Err.new("#{one.class}".sub(/^RethinkDB::/,""), one.message, false)
    end
    cmp = one.class.name <=> two.class.name
    return cmp if cmp != 0
    if not two.regex
      one_msg = one.message.sub(/:\n.*|:$/, ".")
      [one.type, one_msg] <=> [two.type, two.message]
    else
      if (Regexp.compile two.type) =~ one.type and
          (Regexp.compile two.message) =~ one.message
        return 0
      end
      return -1
    end

  when "Array"
    if one.respond_to? :to_a
      one = one.to_a
    end
    cmp = one.class.name <=> two.class.name
    return cmp if cmp != 0
    cmp = one.length <=> two.length
    return cmp if cmp != 0
    return one.zip(two).reduce(0){ |acc, pair|
      acc == 0 ? cmp_test(pair[0], pair[1]) : acc
    }

  when "Hash"
    cmp = one.class.name <=> two.class.name
    return cmp if cmp != 0
    one = Hash[ one.map{ |k,v| [k.to_s, v] } ]
    two = Hash[ two.map{ |k,v| [k.to_s, v] } ]
    cmp = one.keys.sort <=> two.keys.sort
    return cmp if cmp != 0
    return one.keys.reduce(0){ |acc, k|
      acc == 0 ? cmp_test(one[k], two[k]) : acc
    }

  when "Bag"
    return cmp_test(one.sort{ |a, b| cmp_test a, b },
                    two.items.sort{ |a, b| cmp_test a, b })
    
  else
    begin
      cmp = one <=> two
      return cmp if cmp != nil
      return one.class.name <=> two.class.name
    rescue
      return one.class.name <=> two.class.name
    end
  end
end

def eval_env; binding; end
$defines = eval_env

# $js_conn = RethinkDB::Connection.new('localhost', JSPORT)

$cpp_conn = RethinkDB::Connection.new('localhost', CPPPORT)

$test_count = 0
$success_count = 0

def test src, expected, name
  $test_count += 1
  begin
    query = eval src, $defines
  rescue Exception => e
    do_res_test name, src, e, expected
    return
  end

  begin
    do_test query, expected, $cpp_conn, name + '-CPP', src
    # do_test query, expected, $js_conn, name + '-JS', src
  rescue Exception => e
    do_res_test name, src, e, expected
  end
end

at_exit do
  puts "Ruby: #{$success_count} of #{$test_count} tests passed. #{$test_count - $success_count} tests failed."
end

def do_test query, expected, con, name, src
  begin
    res = query.run(con)
  rescue Exception => exc
    res = err(exc.class.name.sub(/^RethinkDB::/, ""), exc.message.split("\n")[0], "TODO")
  end
  return do_res_test name, src, res, expected
end

def do_res_test name, src, res, expected
  begin
    if expected != ''
      expected = eval expected.to_s, $defines
    else
      expected = NoError
    end
    if ! eq_test(res, expected)
      fail_test name, src, res, expected
      return false
    else
      $success_count += 1
      return true
    end
  rescue Exception => e
    puts "#{name}: Error: #{e} when comparing #{show res} and #{show expected}"
    return false
  end
end

def fail_test name, src, res, expected
      puts "TEST FAILURE: #{name}"
      puts "TEST BODY: #{src}" 
      puts "\tVALUE: #{show res}"
      puts "\tEXPECTED: #{show expected}"
      puts; puts;
end

def define expr
  eval expr, $defines
end

True=true
False=false

