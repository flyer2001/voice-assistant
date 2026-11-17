"""Prototype STT selection; cloud recognition requires an explicit provider.

SpeechKit v1 accepts at most 30 seconds of mono PCM per request. Longer
utterances are sent in ordered, non-overlapping pieces with bounded I/O
concurrency. Word boundaries across pieces are a research limitation.
"""
from concurrent.futures import ThreadPoolExecutor
import json
import urllib.parse
import urllib.request

PCM_BYTES_PER_SECOND = 8000 * 2
CHUNK_BYTES = 30 * PCM_BYTES_PER_SECOND
MAX_BYTES = 121 * PCM_BYTES_PER_SECOND


def recognize(pcm, *, provider, whisper, speechkit_headers):
    if provider not in ('whisper', 'speechkit'):
        raise ValueError('Unknown STT provider')
    if len(pcm) % 2 or len(pcm) > MAX_BYTES:
        raise ValueError('Invalid mono 8 kHz PCM utterance')
    if provider == 'whisper':
        return whisper(pcm)
    if not pcm:
        return ''

    headers = speechkit_headers() | {'Content-Type': 'application/octet-stream'}
    query = urllib.parse.urlencode({
        'format': 'lpcm', 'sampleRateHertz': 8000, 'lang': 'ru-RU',
    })
    url = 'https://stt.api.cloud.yandex.net/speech/v1/stt:recognize?' + query

    def part(audio):
        request = urllib.request.Request(url, audio, headers)
        with urllib.request.urlopen(request, timeout=20) as response:
            result = json.loads(response.read(65537))
        if not isinstance(result.get('result'), str):
            raise ValueError('SpeechKit response has no text')
        return result['result'].strip()

    pieces = [pcm[i:i+CHUNK_BYTES] for i in range(0, len(pcm), CHUNK_BYTES)]
    if len(pieces) == 1:
        texts = [part(pieces[0])]
    else:
        # map preserves the spoken order even if HTTP responses finish out of order.
        # Any failed part fails the utterance rather than claiming partial success.
        with ThreadPoolExecutor(max_workers=min(4, len(pieces))) as pool:
            texts = list(pool.map(part, pieces))
    return ' '.join(text for text in texts if text)
