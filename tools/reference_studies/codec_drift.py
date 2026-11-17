"""Render a square found-footage / codec-failure study from original procedural assets."""

import argparse
from pathlib import Path
import subprocess

import cv2 as cv
import numpy as np

from codec_drift_score import synthesize

SIZE = 480
FPS = 30
FRAMES = 1367
DURATION = FRAMES / FPS
Y, X = np.indices((SIZE, SIZE), dtype=np.float32)
U, V = (X + .5) / SIZE, (Y + .5) / SIZE
RAD = ((U - .50)**2 + (V - .47)**2) * .72
TIMECUTS = (0, 1.07, 2.88, 8.20, 11.29, 13.32, 16.17, 20.54, 21.32,
            25.68, 28.44, 30.05, 32.14, 34.61, 35.50, 38.31, 39.63, 45.32)


def u8(a):
    return np.clip(a, 0, 255).astype(np.uint8)


def noise(rng, w, h, at=SIZE):
    return cv.resize(rng.standard_normal((h, w)).astype(np.float32), (at, at),
                     interpolation=cv.INTER_CUBIC)


def text(image, value, x, y, scale, color, weight=1):
    cv.putText(image, value, (x, y), cv.FONT_HERSHEY_SIMPLEX, scale, color, weight, cv.LINE_AA)


def polygon(image, vertices, color):
    cv.fillPoly(image, [np.int32(vertices)], color, cv.LINE_AA)


def tint(texture, color):
    return texture[..., None] + np.float32(color)


class Study:
    def __init__(self, seed):
        self.seed = seed
        r = np.random.default_rng(seed)
        self.grit = np.stack([noise(r, SIZE, SIZE) for _ in range(12)])
        self.soft = noise(r, 16, 16)
        self.fine = noise(r, 135, 135)
        self.scan = 1 - .035 * (Y % 3 == 0) - .30 * RAD
        self.pressure = noise(r, 21, 17)
        self.mask_roll = noise(r, 36, 6)
        self.forest = [self.landscape(r, canal) for canal in (False, True)]
        self.bark = (10 * noise(r, 80, 4) + 23 * noise(r, 31, 7) +
                     11 * noise(r, 113, 20) + self.fine * 5)
        self.dust = r.uniform(0, 1, (108, 4))
        self.previous = self.held = None
        self.buttons = self.make_panel()

    @staticmethod
    def landscape(rng, canal):
        # A deep layered plate: hazy saplings, dappled understory and near-field bark.
        n = 848
        y, x = np.indices((n, n), dtype=np.float32) / n
        foliage = 16 * noise(rng, 20, 21, n) + 10 * noise(rng, 80, 54, n) + 5 * noise(rng, 240, 199, n)
        path = np.exp(-((x - (.55 + .11 * np.sin(y * 4))) / (.045 + .32 * y**3))**2)
        ground = np.clip((y - .37 - foliage * .0022) * 11, 0, 1)
        light = np.maximum(0, noise(rng, 19, 12, n)) * ground
        image = tint(foliage * .59 + 21 * ground + light * 17, (59, 78, 62))
        image += (ground * path)[..., None] * np.float32((30, 17, 4))
        image = u8(image)
        for _ in range(7000):
            xx, yy = rng.integers(0, n, 2)
            if yy >= n * .41 or rng.random() < .28:
                size = int(1 + rng.random()**2 * (2 + 7 * yy / n))
                base = image[yy, xx].astype(float)
                col = np.clip(base + rng.normal(0, 16) + rng.uniform(-1, 1) * np.array([7, 13, 1]), 0, 255)
                cv.ellipse(image, (xx, yy), (size, max(1, size // 3)), rng.integers(-75, 75),
                           0, 360, tuple(col), -1, cv.LINE_AA)
        for depth in (.15, .41, .74, 1.0):
            for _ in range(round(27 - 22 * depth)):
                xx = int(rng.uniform(-55, n + 55))
                if depth > .7 and abs(xx / n - .55) < .13:
                    xx += 160 if xx >= .55*n else -160
                yy = int((.44 + .51 * depth + rng.uniform(-.08, .08)) * n)
                w = int(rng.uniform(6, 40) * depth + 2)
                slope = int(rng.normal(0, 29) * depth)
                base = rng.uniform(34, 76) + 27 * (1 - depth)
                poly = [(xx - w, yy), (xx - w * .72 + slope, yy * .55),
                        (xx - w * .46 + slope * 2, -5), (xx + w * .50 + slope * 2, -5),
                        (xx + w * .74 + slope, yy * .55), (xx + w, yy-4)]
                polygon(image, poly, (base + 8, base + 4, base - 3))
                for i in range(max(5, int(w * .8))):
                    off = rng.uniform(-.49, .49) * w
                    b = float(np.clip(base + rng.normal(0, 17), 8, 145))
                    cv.line(image, (int(xx + off), yy - rng.integers(4, 31)),
                            (int(xx + 2 * slope + off * .75), 0), (b + 7, b + 3, b),
                            1 + int(i % 7 == 0), cv.LINE_AA)
        if canal:
            edge = .58 + .05 * np.sin(y * 12) + .15 * y + .011 * noise(rng, 31, 35, n)
            water = 11 * noise(rng, 15, 5, n) + 4 * noise(rng, 29, 173, n)
            water -= 24 * np.maximum(0, np.sin(48 * x + noise(rng, 8, 6, n) * .7)) ** 6
            bank = np.clip((edge - x) * 170, 0, 1)[..., None]
            image = u8(image * (1 - bank) + tint(water, (36, 72, 63)) * bank)
            for i in range(40):
                yy = rng.uniform(.25, 1)
                xx = .57 + .05 * np.sin(yy * 12) + .15 * yy + rng.uniform(-.013, .09)
                for j in range(rng.integers(2, 6)):
                    h = rng.integers(9, 68)
                    px, py = int(xx * n), int(yy * n)
                    dx = int(rng.normal(0, h * .42))
                    b = rng.uniform(83, 143)
                    cv.line(image, (px, py), (px + dx, py - h), (b, b - 6, b * .64), 1, cv.LINE_AA)
        return cv.GaussianBlur(image, (3, 3), .53)

    def woodland(self, t, which):
        if which == 5:
            bark = cv.remap(self.bark, (X + 28 * np.sin(V * 6 + t) + 56 * t).astype(np.float32),
                            Y, cv.INTER_LINEAR, borderMode=cv.BORDER_WRAP)
            image = u8(tint(bark + 31 * U, (73, 73, 76)))
            portion = int(SIZE * (.66 + .10 * np.sin(t * 3)))
            image[:, portion:] = u8(tint(self.soft[:, portion:] * 19, (156, 162, 145)))
            return image
        plate = self.forest[int(which in (3, 4))]
        w = 645 - 29 * t + 13 * np.sin(t * 2.3)
        xx = 113 + 77 * np.sin(t * .63 + which * 1.4) + np.sin(t * 9.2) * 4
        yy = 221 + (52 if which < 3 else -48) + 39 * np.cos(t * .69 + which) + 5 * np.cos(t * 17)
        mx = xx + (U - .5) * w + w * .07 * (V - .5) * np.sin(t * 2.7) + (848 - w) / 2
        my = yy + V * w * .91 - w * .02 * np.sin(t * 2.7) * (U - .5)
        return cv.remap(plate, mx.astype(np.float32), my.astype(np.float32),
                        cv.INTER_LINEAR, borderMode=cv.BORDER_REFLECT_101)

    def fish(self, t):
        bg = tint(self.soft * 7 + 11 * (1 - V), (91, 131, 125))
        for x0, y0, sz, phase in self.dust[:25]:
            x = int(((x0 - t * .044) % 1) * SIZE)
            y = int(((y0 - t * .03) % 1) * SIZE)
            cv.circle(bg, (x, y), int(1 + sz * 3), (130, 166, 153), 1)
        x0 = .82 - t * .157 + .043 * np.sin(t * 1.8)
        y0 = .52 + .064 * np.sin(t * 2.3)
        x, y = (U - x0) / .30, (V - y0) / .23
        a = np.sin(12 * t) * .12
        tx, ty = x + a * y, y - a * x
        r = (tx**2 + ty**2 * (1 - .17 * tx))
        rim = np.clip((1 - r) * 28, 0, 1)
        light = np.sqrt(np.clip(1-r, 0, 1)) * (.61 - .24 * ty - .19 * tx)
        scales = 4 * np.sin(60 * tx + 5 * np.sin(46 * ty)) * np.cos(57 * ty) + 3 * self.fine
        body = np.stack((178 + light * 91 + scales - 37 * tx,
                         80 + light * 119 + scales - 39 * tx,
                         28 + light * 110 + scales + 51 * np.maximum(0, tx)), axis=2)
        tail_x = (x0 + .31) * SIZE
        tail_y = y0 * SIZE
        flare = (.15 + .09 * np.sin(15 * t)) * SIZE
        polygon(bg, [(tail_x-16, tail_y), (tail_x+flare, tail_y-56),
                     (tail_x+flare-17, tail_y), (tail_x+flare+8, tail_y+66)], (47, 54, 122))
        polygon(bg, [((x0-.10)*SIZE, tail_y-56), ((x0+.05)*SIZE, tail_y-146),
                     ((x0+.20)*SIZE, tail_y-100), ((x0+.24)*SIZE, tail_y-48)], (39, 50, 103))
        for j in range(10):
            cv.line(bg, (int(tail_x-18), int(tail_y)), (int(tail_x+flare-j), int(tail_y+(j-4)*10)),
                    (47.+j*3, 76., 127.+j*4), 1, cv.LINE_AA)
        gill = np.exp(-((tx + .23 - .13*ty**2) * 27)**2) * np.exp(-(ty * 1.35)**6)
        body -= gill[..., None] * 37
        eye_x, eye_y = int((x0-.16)*SIZE), int((y0-.041)*SIZE)
        image = u8(bg * (1-rim[..., None]) + body * rim[..., None])
        for axes, col in (((17, 24), (123, 102, 41)), ((13, 20), (53, 159, 179)),
                          ((8, 15), (8, 17, 28)), ((3, 5), (200, 228, 207))):
            cv.ellipse(image, (eye_x, eye_y), axes, -16, 0, 360, col, -1, cv.LINE_AA)
        cv.ellipse(image, (int((x0-.286)*SIZE), int((y0+.09)*SIZE)), (7, 3), 24, 10, 200,
                   (53, 33, 23), 2, cv.LINE_AA)
        return image

    def plankton(self, t, cold):
        bg = tint(self.soft * 4 + 22 * np.maximum(0, 1 - (V - .5)**2 * 6),
                  (14, 41, 70) if cold else (42, 13, 76))
        color = np.float32((248, 241, 116) if cold else (255, 70, 75))
        for x0, y0, z, p in self.dust:
            cv.circle(bg, (int(x0 * SIZE), int(((y0 - t * (.018 + .013*z)) % 1) * SIZE)),
                      int(1 + (z > .76)), tuple(color * (.15 + .24 * p)), -1, cv.LINE_AA)
        cells = ((.09, .18, .12, .18, -.6, .28), (.90, .36, .12, .17, 1.8, .27),
                 (.17, .86, .15, .24, .89, .34), (.7, .93, .15, .18, -.7, .27),
                 (.52, .53, .156, .336, -.43, 1.0))
        for i, (cx, cy, sx, sy, angle, power) in enumerate(cells):
            x, y = U - cx - .047*np.sin(.85*t+i), V - cy - .034*np.sin(1.7*t+i*2)
            a = angle + .20 * np.sin(t * 1.25 + i)
            xx = (x*np.cos(a) + y*np.sin(a))/(sx*(1 + .11*np.sin(t*2.8+i)))
            yy = (-x*np.sin(a)+y*np.cos(a))/sy
            yy *= 1 + .06*np.sin(xx*8+t)
            r = np.sqrt(xx**2+yy**2)
            inner = np.clip(1-r, 0, 1)
            angle_map = np.arctan2(yy, xx)
            glow = .29*np.exp(-((r-1)*19)**2) + .16*np.exp(-((r-1)*5.0)**2)
            glow += inner**.63 * .48
            glow += .15 * np.sin(angle_map*51+3*r+2*t)**6 * np.exp(-((r-.85)*6.0)**2) * (r < 1)
            for p in (-.29, .22):
                glow += .21 * np.exp(-((xx+.20)*5.8)**2 - ((yy-p)*5.6)**2)
            glow *= power
            bg += glow[..., None] * color + glow[..., None]**2 * np.array((97, 64, 41))
        return u8(bg)

    def crt(self, t, desk=False):
        image = u8(tint(self.bark * .29 + (1 - V) * 22, (44, 37, 31)))
        if desk:
            polygon(image, [(0, 337), (480, 311), (480, 480), (0, 480)], (38, 37, 29))
            for i in range(5):
                yy = 345 + i * 20
                cv.line(image, (0, yy), (479, yy - 25), (67, 64, 54), 2, cv.LINE_AA)
            x1, y1, x2, y2 = 83, 111, 372, 328
            cv.rectangle(image, (149, 291), (295, 363), (31, 39, 34), -1)
        else:
            x1, y1, x2, y2 = -7, 60, 481, 422
        cv.rectangle(image, (x1, y1), (x2, y2), (123, 128, 113) if not desk else (51, 49, 44), -1)
        a, b = max(0, x1+21), min(SIZE, x2-21)
        c, d = y1+19, y2-(60 if not desk else 27)
        v = V[c:d, a:b]
        u = U[c:d, a:b]
        rolling = .7 + .24*np.sin(v*115-13*t)**2
        static = self.grit[int(t * FPS) % 12, c:d, a:b]
        if desk:
            face = np.clip(1-((u-.49)/.086)**2-((v-.46)/.111)**2, 0, 1)
            shade = 44 + 156 * face**.4 + static*11
        else:
            shade = 155 + 78*np.exp(-((u-.53)*2.3)**2) + 9*static
            shade -= (np.sin(u * 49) > .94) * 31
        image[c:d, a:b] = u8(tint(shade * rolling * (1-.13*(Y[c:d,a:b]%3 == 0)), (0, 3, 5)))
        for yy in range(d+14, y2-8, 4):
            cv.line(image, (x1+26, yy), (x2-26, yy), (84, 88, 81), 1, cv.LINE_AA)
        return image

    def eye(self, t):
        x, y = U - .65 - .035*np.sin(t*4), V - .55 - .025*np.sin(t*5)
        y = y + .13*x
        r = np.sqrt(x*x + y*y)
        angle = np.arctan2(y, x)
        crease = .19*(1 - (x/.40)**2)
        opening = np.clip((crease - abs(y))*122, 0, 1)
        skin = tint(13*self.soft + 8*self.fine + 43*U - 30*np.exp(-((abs(y)-crease)*26)**2), (141, 105, 89))
        white = tint(16*self.soft + 18*(1-np.abs(y)*5), (163, 161, 151))
        iris = tint(48*np.sin(angle*83 + np.sin(angle*19))**2 + 15*self.soft +
                    18*np.exp(-((r-.079)*26)**2), (37, 69, 79))
        iris_rim = np.clip((.142-r)*145, 0, 1)
        pupil = np.clip((.054-r)*145, 0, 1)
        glint = np.exp(-((x+.034)*79)**2-((y+.056)*47)**2)
        fill = (iris*(1-pupil[...,None]) + 11*pupil[...,None] + glint[...,None]*184)
        fill = fill*iris_rim[...,None] + white*(1-iris_rim[...,None])
        return u8(skin*(1-opening[...,None]) + fill*opening[...,None])

    def make_panel(self):
        image = u8(tint(.50*self.bark + 32*np.exp(-((U-.36)*6)**2), (57, 57, 54)))
        for i in range(8):
            for j in range(2):
                px, py = 158 + j * 90, 37 + i * 53
                cv.rectangle(image, (px, py), (px+56, py+39), (117, 117, 112), -1)
                cv.rectangle(image, (px+4, py+3), (px+52, py+36), (60, 63, 63), -1)
                text(image, str(23 - i*2 - j), px+7, py+27, .66, (208, 201, 183), 2)
        cv.rectangle(image, (252, 199), (300, 232), (217, 204, 162), 2, cv.LINE_AA)
        return image

    def elevator(self, t, display):
        if not display:
            matrix = np.float32([[.93, -.17, 46+10*np.sin(t*3)], [.04, 1.01, -7+17*np.sin(t*2)]])
            return cv.warpAffine(self.buttons, matrix, (SIZE, SIZE), borderMode=cv.BORDER_REPLICATE)
        image = u8(tint(11*self.soft+5*self.fine+25*U, (95, 96, 90)))
        polygon(image, [(17, 127), (424, 145), (476, 480), (0, 480)], (28, 29, 28))
        polygon(image, [(70, 142), (73, 480), (76, 480), (75, 142)], (39, 40, 41))
        cv.rectangle(image, (115, 6), (351, 121), (35, 40, 46), -1)
        cv.rectangle(image, (130, 17), (336, 108), (45, 65, 99), -1)
        px, py = 245 + int(3*np.sin(t*3)), 66
        cv.ellipse(image, (px, py), (53, 40), -11, 3, 290, (70, 129, 179), 2, cv.LINE_AA)
        polygon(image, [(148, 44), (194, 44), (171, 85)], (212, 224, 222))
        number = 22 - int(np.searchsorted((1.48, 2.64, 3.90, 4.92), t, side='right'))
        text(image, str(number), 203, 89, 1.82, (218, 236, 245), 4)
        image = u8(image + tint(self.grit[0]*1.8, (0, 0, 0)))
        matrix = np.float32([[1.07, .036, -19 + 3*np.sin(t*6)], [-.044, 1.08, 7 + 4*np.cos(t*7)]])
        return cv.warpAffine(image, matrix, (SIZE, SIZE), borderMode=cv.BORDER_REPLICATE)

    def clean(self, cut, t):
        if cut == 0:
            image = self.eye(.5+t)
            for i in range(5):
                x, y = int((.2+.16*i+.1*np.sin(t*9+i))*SIZE), int((.26+.19*np.sin(t*10+i))*SIZE)
                cv.ellipse(image, (x, y), (105-i*12, 32+i*9), 33*i + int(t*140), 0, 320,
                           (23+i*17, 25+i*14, 25+i*12), 22, cv.LINE_AA)
            return image
        if cut <= 5:
            return self.woodland(t, cut)
        if cut <= 7:
            return self.fish(t + (2.8 if cut == 7 else 0))
        if cut <= 9:
            return self.plankton(t, cut == 9)
        if cut in (10, 12):
            return self.crt(t, cut == 12)
        if cut == 11:
            return self.eye(t)
        if cut in (13, 14):
            s = self.bark*.64 + 28*self.soft + 34*np.sin(U*18+t)*(1 - V)
            if cut == 14:
                flood = self.pressure*11 + self.soft*26 + s - 48 * np.sin(V*9 + t*2.7)
                return u8(tint(s, (115, 111, 100))*.28 +
                          np.where(flood[...,None]>0, (236, 220, 78), (41, 42, 48))*.72)
            return u8(tint(s, (119, 118, 107)))
        if cut <= 16:
            return self.elevator(t, cut == 16)
        return np.zeros((SIZE,SIZE,3), np.uint8)

    def contaminate(self, image, frame, cut, local):
        # Freeze old macroblocks and refresh them at different rates. Bias toward
        # the water/ground in the early cuts so the corruption appears attached.
        if self.previous is None:
            self.previous = self.held = image.copy()
        group = frame // 4
        r = np.random.default_rng(np.random.SeedSequence([self.seed, group]))
        level = (.38, .23, .38, .44, .45, .63, .59, .96, .05, .08,
                 .20, .12, .18, .18, .55, .22, .11, 0)[cut]
        if cut == 16:
            level *= .31
        phase = .5 + .5*np.sin(local*4.1 + cut)
        if frame % 13 == 0:
            self.held = self.previous.copy()
        if cut in (1, 2, 3, 4, 5, 6, 7):
            edge = np.mean(np.abs(image.astype(np.float32) - self.held), axis=2)
            motion = cv.resize(cv.resize(edge, (24, 24), interpolation=cv.INTER_AREA),
                               (SIZE,SIZE), interpolation=cv.INTER_NEAREST) / 75
            field = cv.resize(r.random((24,24)).astype(np.float32), (SIZE,SIZE), interpolation=cv.INTER_NEAREST)
            if cut <= 2:
                loc = np.exp(-((U - .54 - .23*np.sin(local))*3.6)**2) * np.clip((V - .16)*1.34, 0, 1)
            elif cut <= 4:
                loc = np.exp(-((U - .45 - .12*np.sin(local))*7.5)**2)
            elif cut == 5:
                loc = np.clip((U - .51)*3, 0, 1)
            elif cut == 6:
                # Let the silhouette emerge between held groups of blocks.
                loc = .27 + .52 * np.sin(10*U + 4*V + local*2.4)**2
                if local > 1.42:
                    loc *= 1 - .92 * np.exp(-((U-.45)*4.1)**2-((V-.52)*2.8)**2)
            else:
                loc = .16 + .64 * np.sin(26*V + 2*U + local*4)**2
            active = (field*.44 + (loc + np.clip(motion, 0, .47)*.54)*level + self.pressure*.045
                      > (.68 - .065*phase))
            residue = np.roll(self.held, (int(r.integers(-8, 9)), int(r.integers(-16, 17))),
                              axis=(0, 1)).astype(np.float32)
            palette = np.float32((32, 235, 37) if cut <= 2 or cut == 7 else
                                 ((84, 227, 158) if cut < 5 else (124, 167, 220)))
            dye = (palette + (residue.mean(axis=2)[...,None]-104)*.44
                   + (field[...,None] - .62) * np.float32((95, 31, -91)))
            image = np.where(active[...,None], u8(.29*residue + .71*dye), image)
            if cut == 7:
                image = u8(image * (.62 + .25*np.sin(V*38 + local*2)**2)[...,None])
            if cut in (3, 4, 5) and (frame % 17 < 9):
                x = int((.43+.13*np.sin(local*2.2) + (.28 if cut == 5 else 0))*SIZE)
                col = image[:, x:x+2].copy()
                image[27:SIZE-53, x:x+10] = np.repeat(col[27:SIZE-53], 5, axis=1)
        # Horizontal read errors move blocks, then red/blue slip around the luma.
        if r.random() < level*.83:
            for _ in range(int(2 + level*6)):
                row = r.integers(0, SIZE-4)
                end = min(SIZE, row+r.integers(3, 19+int(level*22)))
                image[row:end] = np.roll(image[row:end], int(r.normal(0, 24*level)), axis=1)
        loss = round(2 + level*6) if level >= .18 else 0
        if loss and (cut in (6, 7, 14) or frame % 21 <= 7):
            image[:,:,0] = np.roll(image[:,:,0], loss, axis=1)
            image[:,:,2] = np.roll(image[:,:,2], -loss, axis=1)
        self.previous = image.copy()
        return image

    def frame(self, i):
        time = i / FPS
        cut = int(np.searchsorted(TIMECUTS, time, side='right') - 1)
        if cut == len(TIMECUTS) - 1:
            return np.zeros((SIZE,SIZE,3), np.uint8)
        local = time - TIMECUTS[cut]
        image = self.contaminate(self.clean(cut, local), i, cut, local)
        analog = .53 if cut in (8, 9, 16) else 1
        y = image.astype(np.float32) * self.scan[...,None]
        y += ((2.8 + 2*analog) * self.grit[i % 12] + 1.8 * np.sin(i*.7+V*28))[...,None]
        small = cv.resize(y, (360, 360), interpolation=cv.INTER_AREA)
        return u8(cv.resize(small, (SIZE, SIZE), interpolation=cv.INTER_LINEAR))


def render(target, score, seed):
    synthesize(score, DURATION, seed)
    study = Study(seed)
    cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo',
           '-pixel_format', 'rgb24', '-video_size', f'{SIZE}x{SIZE}', '-framerate', str(FPS),
           '-i', '-', '-i', str(score), '-c:v', 'libx264', '-preset', 'medium', '-crf', '19',
           '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', str(target)]
    with subprocess.Popen(cmd, stdin=subprocess.PIPE) as encoder:
        try:
            for i in range(FRAMES):
                encoder.stdin.write(study.frame(i).tobytes())
                if i % (10 * FPS) == 0:
                    print(f'{i // FPS}s / {DURATION:.2f}s', flush=True)
        except BaseException:
            encoder.terminate()
            raise
        finally:
            encoder.stdin.close()
        if encoder.wait() != 0:
            raise RuntimeError('FFmpeg did not finish encoding the study')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seed', type=int, default=1157328)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    cv.setNumThreads(1)
    render(args.output / 'codec_drift.mp4', args.output / 'codec_drift_score.wav', args.seed)
