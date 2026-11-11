// Web Audio API 離線 4X 變速與定長切片引擎 (供 Web 端避開指紋審查)
(function() {
  function audioBufferToWav(buffer, startSec, durationSec) {
    const sampleRate = buffer.sampleRate;
    const numChannels = buffer.numberOfChannels;
    const startOffset = Math.floor(startSec * sampleRate);
    const endOffset = Math.min(buffer.length, Math.floor((startSec + durationSec) * sampleRate));
    const numSamples = Math.max(0, endOffset - startOffset);

    const blockAlign = numChannels * 2;
    const byteRate = sampleRate * blockAlign;
    const dataSize = numSamples * blockAlign;
    const bufferSize = 44 + dataSize;
    const arrayBuffer = new ArrayBuffer(bufferSize);
    const view = new DataView(arrayBuffer);

    function writeString(offset, string) {
      for (let i = 0; i < string.length; i++) {
        view.setUint8(offset + i, string.charCodeAt(i));
      }
    }

    writeString(0, 'RIFF');
    view.setUint32(4, 36 + dataSize, true);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, numChannels, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, byteRate, true);
    view.setUint16(32, blockAlign, true);
    view.setUint16(34, 16, true);
    writeString(36, 'data');
    view.setUint32(40, dataSize, true);

    const channels = [];
    for (let c = 0; c < numChannels; c++) {
      channels.push(buffer.getChannelData(c));
    }

    let offset = 44;
    for (let i = startOffset; i < endOffset; i++) {
      for (let c = 0; c < numChannels; c++) {
        let sample = channels[c][i];
        sample = Math.max(-1, Math.min(1, sample));
        const s16 = sample < 0 ? sample * 0x8000 : sample * 0x7FFF;
        view.setInt16(offset, s16, true);
        offset += 2;
      }
    }

    return new Uint8Array(arrayBuffer);
  }

  window.processAndSlice4XWeb = async function(rawBytes, speed, sliceSec) {
    speed = speed || 4.0;
    sliceSec = sliceSec || 10.0;

    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextClass) {
      throw new Error('當前瀏覽器不支援 Web Audio API');
    }
    const audioCtx = new AudioContextClass();

    let arrayBuffer;
    if (rawBytes instanceof ArrayBuffer) {
      arrayBuffer = rawBytes.slice(0);
    } else if (rawBytes && rawBytes.buffer) {
      arrayBuffer = rawBytes.buffer.slice(rawBytes.byteOffset, rawBytes.byteOffset + rawBytes.byteLength);
    } else {
      throw new Error('無效的音訊數據類型');
    }

    const decoded = await audioCtx.decodeAudioData(arrayBuffer);
    const origDuration = decoded.duration;
    const spedDuration = origDuration / speed;
    const sampleRate = decoded.sampleRate;
    const numChannels = decoded.numberOfChannels;
    const spedLength = Math.max(1, Math.ceil(spedDuration * sampleRate));

    const offlineCtx = new OfflineAudioContext(numChannels, spedLength, sampleRate);
    const source = offlineCtx.createBufferSource();
    source.buffer = decoded;
    source.playbackRate.value = speed;
    source.connect(offlineCtx.destination);
    source.start(0);

    const spedBuffer = await offlineCtx.startRendering();

    const bounds = [];
    let pos = 0.0;
    while (pos + sliceSec <= spedDuration) {
      bounds.push([pos, pos + sliceSec]);
      pos += sliceSec;
    }
    const rem = spedDuration - pos;
    if (rem >= 5.0 || bounds.length === 0) {
      if (rem > 0.05) bounds.push([pos, spedDuration]);
    } else if (rem > 0.05 && bounds.length > 0) {
      const last = bounds.pop();
      bounds.push([last[0], spedDuration]);
    }

    const slices = [];
    for (let i = 0; i < bounds.length; i++) {
      const start = bounds[i][0];
      const end = bounds[i][1];
      const dur = end - start;
      const sliceIndex = i + 1;
      const sliceFileName = 'slice_' + String(sliceIndex).padStart(2, '0') + '.wav';
      const wavBytes = audioBufferToWav(spedBuffer, start, dur);

      slices.push({
        index: sliceIndex,
        fileName: sliceFileName,
        timelineStartSec: start * speed,
        timelineEndSec: end * speed,
        spedDurationSec: dur,
        speed: speed,
        bytes: wavBytes
      });
    }

    return slices;
  };
})();
