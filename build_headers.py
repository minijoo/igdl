import json
from datetime import datetime, timezone
from pathlib import Path

USERNAME = '7ro.jordan'


def load(path):
	p = Path(path)
	return json.loads(p.read_text()) if p.exists() else []


def to_item(record, source):
	return {
		'pk': record.get('pk'),
		'short_code': record.get('shortcode'),
		'original_width': record.get('original_width'),
		'original_height': record.get('original_height'),
		'video_duration': record.get('video_duration'),
		'like_count': record.get('like_count'),
		'caption_text': record.get('caption'),
		'comment_count': record.get('comment_count'),
		'username': record.get('username'),
		'user_pk': record.get('user_pk'),
		'user_profile_pic_url': record.get('user_profile_pic_url'),
		'taken_at': record.get('taken_at'),
		'sources': {source},
	}


def build():
	liked = load('liked_snapshot.json')
	saved = load('saved_snapshot.json')

	# Merge by short_code — a post can be both liked and saved (49 of them,
	# as of the last check), so `sources` is a set/list, not a single value.
	merged = {}
	for record in liked:
		item = to_item(record, 'liked')
		merged[item['short_code']] = item
	for record in saved:
		item = to_item(record, 'saved')
		existing = merged.get(item['short_code'])
		if existing:
			existing['sources'] |= item['sources']
		else:
			merged[item['short_code']] = item

	items = list(merged.values())
	for item in items:
		item['sources'] = sorted(item['sources'])

	headers = {
		'retrieved_at': int(datetime.now(timezone.utc).timestamp()),
		'authenticated_user_username': USERNAME,
		'items': items,
	}

	Path('headers.json').write_text(json.dumps(headers, indent=2))
	both = sum(1 for i in items if len(i['sources']) > 1)
	print(
		f'headers.json: {len(items)} items '
		f'({len(liked)} liked, {len(saved)} saved, {both} in both)'
	)


if __name__ == '__main__':
	build()
