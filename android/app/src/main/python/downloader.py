import json
import os
import yt_dlp

def get_video_info(url):
    try:
        ydl_opts = {
            'quiet': True,
            'no_warnings': True,
            'extract_flat': False,
        }
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            return json.dumps({
                'success': True,
                'title': info.get('title', 'Unknown'),
                'artist': info.get('uploader') or info.get('channel') or info.get('artist') or 'Unknown Artist',
                'thumbnail': info.get('thumbnail'),
                'duration': info.get('duration'),
                'id': info.get('id'),
            })
    except Exception as e:
        return json.dumps({'success': False, 'error': str(e)})

def download_audio(url, output_dir, file_name):
    try:
        os.makedirs(output_dir, exist_ok=True)
        out_tmpl = os.path.join(output_dir, f"{file_name}.%(ext)s")
        ydl_opts = {
            'format': 'bestaudio/best',
            'outtmpl': out_tmpl,
            'quiet': True,
            'no_warnings': True,
        }
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            target_path = ydl.prepare_filename(info)
            return json.dumps({
                'success': True,
                'path': target_path,
                'title': info.get('title', file_name),
                'artist': info.get('uploader') or info.get('channel') or info.get('artist') or 'Unknown',
            })
    except Exception as e:
        return json.dumps({'success': False, 'error': str(e)})
