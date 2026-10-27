# Development data. Idempotent: run it as often as you like. Never runs in production.
abort "Refusing to seed demo data in production" if Rails.env.production?

PASSWORD = "password".freeze

sunrise = Organization.find_or_create_by!(name: "Sunrise Clinic")
valley = Organization.find_or_create_by!(name: "Valley Health")

{
  sunrise => { "admin" => :admin, "provider" => :provider, "nurse" => :nurse, "frontdesk" => :front_desk },
  valley => { "admin" => :admin }
}.each do |org, users|
  domain = org.name.split.first.downcase
  users.each do |name, role|
    User.find_or_create_by!(email: "#{name}@#{domain}.test") do |u|
      u.organization = org
      u.first_name = name.capitalize
      u.last_name = "Seed"
      u.role = role
      u.password = PASSWORD
    end
  end
end

# Adds 57 sunrise patients (on top of any existing ones, so about 3 pages of 25). Few last names on purpose, so many patients tie on
# last name (this is what the id tiebreaker protects). created_at is spread out so CREATED_AT order differs
# from LAST_NAME order.
first_names = %w[Alice Bob Carlos Dana Evan Fatima George Hana Ivan Julia Kofi Lena Mateo Nora Omar Priya Quinn Rosa Sam Tara Uma Victor Wen Xavier Yara Zane]
last_names = %w[Smith Smith Smith Adams Brown Brown Clark Davis Evans Garcia Hill Smythe]

57.times do |i|
  first = first_names[i % first_names.size]
  last = last_names[i % last_names.size]
  Patient.find_or_create_by!(organization: sunrise, first_name: first, last_name: last) do |p|
    p.date_of_birth = Date.new(1950, 1, 1) + (i * 397).days
    p.created_at = (60 - i).days.ago
  end
end

# Another tenant, with a matching last name, to prove tenancy in the list and in the count.
%w[Carol Smith Smythe Dan Eve].each_with_index do |first, i|
  Patient.find_or_create_by!(organization: valley, first_name: first, last_name: i.zero? ? "Clark" : "Smith") do |p|
    p.date_of_birth = Date.new(1970, 1, 1) + (i * 500).days
  end
end

puts "Sunrise patients: #{sunrise.patients.count}, Valley patients: #{valley.patients.count}"
