import instaloader
import json
import time
from pathlib import Path

USERNAME = '7ro.jordan'
SLEEP_SECONDS = 3  # be polite between paginated requests

L = instaloader.Instaloader()
L.load_session_from_file(USERNAME)
# L.login(USERNAME, 'QOujeT5tz50J0rQD')
L.context._session.headers['User-Agent'] = (
	'Instagram 10.3.2 (iPhone7,2; iPhone OS 9_3_3; en_US; en-US; scale=2.00; 750x1334) AppleWebKit/420+'
)


def extract(item, media_key=None):
	media = item[media_key] if media_key else item
	caption = media.get('caption') or {}
	user = media.get('user') or {}
	return {
		'shortcode': media.get('code'),
		'pk': media.get('pk'),
		'media_type': media.get('media_type'),
		'taken_at': media.get('taken_at'),
		'original_width': media.get('original_width'),
		'original_height': media.get('original_height'),
		'video_duration': media.get('video_duration'),
		'like_count': media.get('like_count'),
		'comment_count': media.get('comment_count'),
		'username': user.get('username'),
		'user_pk': user.get('pk'),
		'user_profile_pic_url': user.get('profile_pic_url'),
		'caption': caption.get('text'),
	}


def collect_feed(path, media_key, state_file, out_file):
	"""
	state_file tracks two distinct things that must not be conflated:
	  - status: 'in_progress' means a backfill has never reached the end of
	    your history, so `items`/`seen` is NOT a trustworthy complete prefix.
	    'complete' means a full walk has finished at least once.
	  - next_max_id: pagination cursor to resume an in_progress walk from.

	Only when status == 'complete' is it safe to do an incremental run that
	starts from the top and stops as soon as it sees an already-known
	shortcode. Doing that shortcut while status is still in_progress (e.g.
	after a run that only completed one batch) would let a partial batch
	look "caught up" and permanently orphan everything older that was never
	backfilled.
	"""
	state_file = Path(state_file)
	out_file = Path(out_file)

	items = json.loads(out_file.read_text()) if out_file.exists() else []
	seen = {i['shortcode'] for i in items}

	state = json.loads(state_file.read_text()) if state_file.exists() else {}
	status = state.get('status', 'in_progress')

	if status == 'in_progress' and state.get('next_max_id'):
		params = {'max_id': state['next_max_id']}
		incremental = False
	elif status == 'complete':
		params = {}
		incremental = True
	else:
		params = {}
		incremental = False

	total_new = 0
	while True:
		data = L.context.get_json(path=path, host='i.instagram.com', params=params)

		page_new = []
		hit_known = False
		for raw in data['items']:
			record = extract(raw, media_key)
			if record['shortcode'] in seen:
				if incremental:
					hit_known = True
					break
				continue
			seen.add(record['shortcode'])
			page_new.append(record)

		# New items are always more recent than what's already stored, so
		# they go in front to keep the snapshot in recency order. Flushed
		# every page (before the cursor is advanced) so a kill mid-run loses
		# at most the in-flight page, never a silent gap in already-fetched
		# history: if the process dies between this write and the state_file
		# write below, the next run just re-fetches this same page, finds its
		# shortcodes already in `seen`, and skips them as duplicates.
		items = page_new + items if incremental else items + page_new
		total_new += len(page_new)
		out_file.write_text(json.dumps(items, indent=2))

		if hit_known or not data.get('more_available') or not data.get('next_max_id'):
			state_file.write_text(json.dumps({'status': 'complete'}))
			break

		params = {'max_id': data['next_max_id']}
		state_file.write_text(
			json.dumps({'status': 'in_progress', 'next_max_id': data['next_max_id']})
		)

		print(
			f'{path}: +{total_new} so far (more_available={data.get("more_available")})'
		)
		time.sleep(SLEEP_SECONDS)

	print(f'{path}: +{total_new} new (total {len(items)})')
	return items


if __name__ == '__main__':
	liked = collect_feed(
		'api/v1/feed/liked/', None, 'liked_state.json', 'liked_snapshot.json'
	)
	print(f'Liked snapshot: {len(liked)} posts -> liked_snapshot.json')

	saved = collect_feed(
		'api/v1/feed/saved/', 'media', 'saved_state.json', 'saved_snapshot.json'
	)
	print(f'Saved snapshot: {len(saved)} posts -> saved_snapshot.json')
