# == Schema Information
#
# Table name: posts
#
#  id              :integer          not null, primary key
#  title           :string
#  body            :text
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  user_id         :integer
#  picture         :string
#  likes_count     :integer          default("0")
#  published_at    :datetime
#  featured        :boolean          default("false")
#  lead            :text
#  slug            :string
#  responses_count :integer          default("0"), not null
#

class Post < ApplicationRecord

  include Rails.application.routes.url_helpers

  #validates :title, :body, :user_id, presence: true

  validates :body, :user_id, presence: true

  belongs_to :user
  belongs_to :parent, optional: true, class_name: "Post", counter_cache: :responses_count
  has_many :taggings, dependent: :destroy
  has_many :tags, through: :taggings
  has_many :responses, -> { order(created_at: :desc) }, 
            class_name: "Post",
            foreign_key: "parent_id",
            dependent: :destroy


  has_many :responders, through: :responses, source: :user
  has_many :likes, as: :likeable, dependent: :destroy
  has_many :likers, through: :likes, source: :user

  has_many :bookmarks, as: :bookmarkable, dependent: :destroy
  has_many :bookmarkers, through: :bookmarks, source: :user

  delegate :username, to: :user

  scope :recent, -> { order(created_at: :desc) }
  scope :replies, -> { where.not(parent_id: nil) }
  scope :non_replies, -> { where(parent_id: nil) }
  scope :latest, ->(number) { recent.limit(number) }
  scope :top_stories, ->(number) { non_replies.order(likes_count: :desc).limit(number) }
  scope :published, -> { where.not(published_at: nil) }
  scope :drafts, -> { non_replies.where(published_at: nil) }
  scope :featured, -> { non_replies.where(featured: true) }

  #mount_uploader :picture, PictureUploader
  has_one_attached :picture

  before_save :generate_lead!
  # will_pagination configuration
  self.per_page = 5

  #include SearchablePost
  searchkick

  def picture_path
    picture_url = self.picture.attached? ? url_for(self.picture) : nil
  end

  def search_data(options = {})
    self.as_json({
      only: [:title, :body, :published_at, :slug],
      include: {
        user: { only: [:username] },
        #user: {methods: [:avatar_url], only: [:username, :avatar_url] },
        tags: { only: :name }
      }
    })
  end


  extend FriendlyId
  friendly_id :title, use: [ :slugged, :history, :finders ]

  def self.new_draft_for(user)
    post = self.new(user_id: user.id)
    post.save_as_draft
    post
  end

  def self.tagged_with(name)
    Tag.find_by!(name: name).posts
  end

  def related_posts(size: 3)
    Post.joins(:taggings).where.not(id: self.id).where(taggings: { tag_id: self.tag_ids }).distinct.
      published.limit(size).includes(:user)
  end

  def all_tags=(names)
    self.tags = names.split(",").map do |name|
      Tag.first_or_create_with_name!(name)
    end
    RelatedTagsCreator.create(self.tag_ids)
  end

  def all_tags
    tags.map(&:name).join(", ")
  end

  def publish
    self.published_at = Time.zone.now
    self.slug = nil # let FriendlyId generate slug
    save
  end

  def save_as_draft
    self.published_at = nil
    self.slug ||= SecureRandom.urlsafe_base64
    save(validate: false)
  end

  def unpublish
    self.published_at = nil
  end

  def published?
    published_at.present?
  end

  def words
    return "" if plain.blank?
    plain.split(' ')
  end

  def word_count
    words.size
  end

  def generate_lead!
    puts "TO BE DEPRECATED IN FAVOR OF PLAIN VERSION"
  end

=begin
  # Generate a lead which appears in post panel.
  # FIXME: this method needs refactoring or completely different approach
  def generate_lead!
    if self.published?
      post_body = Nokogiri::HTML::Document.parse(self.body)
      if post_body.css('h2').size > 0
        self.lead = post_body.css('h2')[0].to_s
      elsif post_body.css('h3').size > 0
        self.lead = post_body.css('h3')[0].to_s
      elsif post_body.css('p').size > 0
        self.lead = post_body.css('p')[0].to_s
      end
    end
  end
=end

end
