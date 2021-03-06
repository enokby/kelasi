require 'uni_normalize'
require 'securerandom'

class User < ActiveRecord::Base
  authenticates_with_sorcery!
  has_many :atendances
  has_many :universities, through: :atendances

  has_many :introduced_users, class_name: 'User'
  belongs_to :introducer, class_name: 'User', foreign_key: 'user_id'

  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :email, uniqueness: true
  validates :password, length: { minimum: 6 }
  validates :introducer, presence: true
  validates :profile_name, uniqueness: true

  before_create :set_profile_name

  include Tire::Model::Search
  include Tire::Model::Callbacks

  mapping do
    indexes :id, index: :not_analyzed
    indexes :first_name, type: 'string'
    indexes :last_name, type: 'string'
    indexes :universities, as: proc { uni_names }
    indexes :current_universities, as: proc { uni_names true }
  end

  after_touch() { tire.update_index }

  def uni_names current = false
    unis = universities
    unis = currently_attending if current
    return [] if unis.empty?
    unis.map {|u| uni_normalize u.name}
  end

  def self.search_user params
    fname = params[:first_name]
    lname = params[:last_name]
    uname = uni_normalize params[:university]
    return [] if fname.blank? and lname.blank? and uname.blank?
    search load: true do
      query do
        boolean do
          must { string "first_name:#{fname}" } unless params[:first_name].blank?
          must { string "last_name:#{lname}" } unless params[:last_name].blank?
          must { terms :current_universities, [ uname ] } unless params[:university].blank?
        end
      end
    end.results
  end

  def currently_attending
    self.atendances.where(currently_attending: true).includes(:university).map(&:university)
  end

  def set_profile_name

    return unless self.profile_name.blank?

    profile_name  = ( self.first_name.downcase + self.last_name.capitalize ).delete ' '
    profile_name  = self.email.split('@').first unless /^\w+$/ =~ profile_name
    profile_name += Random.rand(9).to_s while User.find_by(profile_name: profile_name)

    self.profile_name = profile_name
  end
end
