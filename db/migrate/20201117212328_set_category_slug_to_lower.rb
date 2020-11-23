# frozen_string_literal: true

class SetCategorySlugToLower < ActiveRecord::Migration[6.0]
  def up
    remove_index(:categories, name: 'unique_index_categories_on_slug')

    categories = DB.query("SELECT id, name, slug, parent_category_id FROM categories")
    updates = {}

    # Resolve duplicate tags by replacing mixed case slugs with new ones
    # extracted from category names
    slugs = categories
      .filter { |category| category.slug != '' }
      .group_by { |category| [category.parent_category_id, category.slug.downcase] }
      .map { |slug, cats| [slug, cats.size] }
      .to_h

    categories.each do |category|
      old_parent_and_slug = [category.parent_category_id, category.slug.downcase]
      next if category.slug == '' ||
              category.slug == category.slug.downcase ||
              slugs[old_parent_and_slug] <= 1

      new_slug = category.name.parameterize
        .tr("_", "-").squeeze('-').gsub(/\A-+|-+\z/, '')
        .truncate(255, omission: '')
      new_slug = '' if (new_slug =~ /[^\d]/).blank?
      new_parent_and_slug = [category.parent_category_id, new_slug]
      next if new_slug == '' ||
              (slugs[new_parent_and_slug].present? && slugs[new_parent_and_slug] > 0)

      updates[category.id] = category.slug = new_slug
      slugs[old_parent_and_slug] -= 1
      slugs[new_parent_and_slug] = 1
    end

    # Reset left conflicting slugs
    slugs = categories
      .filter { |category| category.slug != '' }
      .group_by { |category| [category.parent_category_id, category.slug.downcase] }
      .map { |slug, cats| [slug, cats.size] }
      .to_h

    categories.each do |category|
      old_parent_and_slug = [category.parent_category_id, category.slug.downcase]
      next if category.slug == '' ||
              category.slug == category.slug.downcase ||
              slugs[old_parent_and_slug] <= 1

      updates[category.id] = category.slug = ''
      slugs[old_parent_and_slug] -= 1
    end

    # Update all category slugs
    updates.each do |id, slug|
      execute <<~SQL
        UPDATE categories
        SET slug = '#{PG::Connection.escape_string(slug)}'
        WHERE id = #{id}
      SQL
    end

    # Ensure all slugs are lowercase
    execute "UPDATE categories SET slug = LOWER(slug)"

    add_index(
      :categories,
      'COALESCE(parent_category_id, -1), LOWER(slug)',
      name: 'unique_index_categories_on_slug',
      where: "slug != ''",
      unique: true
    )
  end

  def down
    remove_index(:categories, name: 'unique_index_categories_on_slug')

    add_index(
      :categories,
      'COALESCE(parent_category_id, -1), slug',
      name: 'unique_index_categories_on_slug',
      where: "slug != ''",
      unique: true
    )
  end
end
